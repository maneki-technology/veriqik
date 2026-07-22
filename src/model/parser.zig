const std = @import("std");
const token = @import("token.zig");
const Token = token.Token;
const TokenType = token.TokenType;

const lexer_mod = @import("lexer.zig");
const Lexer = lexer_mod.Lexer;

const ast = @import("ast.zig");
const ArrayList = std.ArrayList;
const testing = std.testing;

const symbol = @import("symbol.zig");
const SymbolId = symbol.SymbolId;
const Interner = symbol.Interner;

const ParserError = error{
    IllegalCharacter,
    UnexpectedToken,
    ReservedKeyword,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: Lexer,
    interner: Interner,
    current_token: Token,
    peek_token: Token,
    // TODO: diagnostic/error state

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        var lexer = Lexer.init(source);
        const interner = Interner.init(allocator, std.math.maxInt(u16));
        const current_token = lexer.next();
        const peek_token = lexer.next();
        const parser = Parser{
            .allocator = allocator,
            .lexer = lexer,
            .interner = interner,
            .current_token = current_token,
            .peek_token = peek_token,
        };
        return parser;
    }

    pub fn deinit(self: *Parser) void {
        self.interner.deinit();
        self.* = undefined;
    }

    fn advance(self: *Parser) void {
        self.current_token = self.peek_token;
        self.peek_token = self.lexer.next();
    }

    pub fn parseModel(self: *Parser) !ast.Model {
        var types: ArrayList(ast.Type) = .empty;
        errdefer {
            for (types.items) |*type_decl| {
                type_decl.deinit(self.allocator);
            }
            types.deinit(self.allocator);
        }

        var conditions: ArrayList(ast.Condition) = .empty;
        errdefer {
            for (conditions.items) |*cond| {
                cond.deinit(self.allocator);
            }
            conditions.deinit(self.allocator);
        }

        while (!self.currentIs(.eof)) {
            switch (self.current_token.type) {
                .kw_type => {
                    const type_decl = try self.parseType();
                    errdefer type_decl.deinit(self.allocator);
                    try types.append(self.allocator, type_decl);
                },
                .kw_condition => {
                    const condition = try self.parseCondition();
                    errdefer condition.deinit(self.allocator);
                    try conditions.append(self.allocator, condition);
                },
                .illegal => {
                    return ParserError.IllegalCharacter;
                },
                else => {
                    return ParserError.UnexpectedToken;
                },
            }
        }

        const owned_types = try types.toOwnedSlice(self.allocator);
        errdefer {
            for (owned_types) |*owned_type| {
                owned_type.deinit(self.allocator);
            }
            self.allocator.free(owned_types);
        }
        const owned_conditions = try conditions.toOwnedSlice(self.allocator);
        errdefer {
            for (owned_conditions) |*owned_condition| {
                owned_condition.deinit(self.allocator);
            }
            self.alloc.free(owned_conditions);
        }

        return .{
            .types = owned_types,
            .conditions = owned_conditions,
        };
    }

    fn parseCondition(self: *Parser) !ast.Condition {
        const condition = try self.consume(.kw_condition);
        const name = try self.parseIdentifier();
        _ = try self.consume(.l_paren);

        var params: ArrayList(ast.Parameter) = .empty;
        errdefer params.deinit(self.allocator);
        try self.parseConditionParams(&params);
        _ = try self.consume(.r_paren);

        const body = try self.skipOpaqueBody();
        return .{
            .name = name,
            .params = try params.toOwnedSlice(self.allocator),
            .span = .{
                .start = condition.start,
                .end = body.end,
            },
        };
    }

    fn parseConditionParams(self: *Parser, params: *ArrayList(ast.Parameter)) !void {
        if (self.currentIs(.r_paren)) return;

        while (true) {
            const param = try self.parseConditionParam();
            try params.append(self.allocator, param);
            if (!self.match(.comma)) break;
        }
    }

    fn parseConditionParam(self: *Parser) !ast.Parameter {
        const name = try self.parseIdentifier();
        _ = try self.consume(.colon);
        const type_ref = try self.parseValueTypeRef();
        return .{
            .name = name,
            .type = type_ref,
            .span = .{
                .start = name.span.start,
                .end = type_ref.span.end,
            },
        };
    }

    fn parseType(self: *Parser) !ast.Type {
        const type_decl = try self.consume(.kw_type);
        const name = try self.parseIdentifier();
        var body_span: ast.Span = undefined;
        var relations: ArrayList(ast.Relation) = .empty;
        errdefer relations.deinit(self.allocator);
        try self.parseBody(&body_span, &relations);

        const owned_relations = try relations.toOwnedSlice(self.allocator);
        errdefer self.alloc.free(owned_relations);

        return .{
            .name = name,
            .relations = owned_relations,
            .span = .{
                .start = type_decl.start,
                .end = body_span.end,
            },
        };
    }

    fn parseBody(self: *Parser, span: *ast.Span, relations: *ArrayList(ast.Relation)) !void {
        const opening = try self.consume(.l_brace);
        while (!self.currentIs(.r_brace)) {
            switch (self.current_token.type) {
                .kw_relation => try self.parseRelation(relations),
                .kw_permission => try self.parsePermission(),
                .illegal => return ParserError.IllegalCharacter,
                .eof => return ParserError.UnexpectedToken,
                else => return ParserError.UnexpectedToken,
            }
        }
        const closing = try self.consume(.r_brace);
        span.* = .{
            .start = opening.start,
            .end = closing.end,
        };
    }

    fn parseRelation(self: *Parser, relations: *ArrayList(ast.Relation)) !void {
        const relation_decl = try self.consume(.kw_relation);
        const name = try self.parseIdentifier();
        var cardinality: ?ast.Cardinality = null;
        if (self.match(.l_bracket)) {
            cardinality = .{ .max = null };
            switch (self.current_token.type) {
                .range => {
                    _ = try self.consume(.range);
                    if (self.currentIs(.integer)) {
                        cardinality.?.max = try self.parseInteger();
                    }
                    _ = try self.consume(.r_bracket);
                },
                .integer => {
                    cardinality.?.min = try self.parseInteger();
                    _ = try self.consume(.range);
                    if (self.currentIs(.integer)) {
                        cardinality.?.max = try self.parseInteger();
                    }
                    _ = try self.consume(.r_bracket);
                },
                .illegal => return ParserError.IllegalCharacter,
                else => return ParserError.UnexpectedToken,
            }
        } else if (self.match(.r_bracket)) {
            return ParserError.UnexpectedToken;
        }
        _ = try self.consume(.colon);
        var expr_span: ast.Span = undefined;
        try self.skipRelationExpression(&expr_span);
        try relations.append(self.allocator, .{
            .name = name,
            .cardinality = cardinality,
            .span = .{
                .start = relation_decl.start,
                .end = expr_span.end,
            },
        });
    }

    fn skipRelationExpression(self: *Parser, span: *ast.Span) !void {
        // Empty expression
        if (self.currentIs(.kw_relation) or
            self.currentIs(.kw_permission) or
            self.currentIs(.r_brace) or
            self.currentIs(.eof))
        {
            return ParserError.UnexpectedToken;
        }

        const start = self.current_token.start;
        var end = self.current_token.end;
        while (true) {
            switch (self.current_token.type) {
                .kw_relation, .kw_permission, .r_brace, .eof => break,
                .illegal => return ParserError.IllegalCharacter,
                else => {
                    end = self.current_token.end;
                    self.advance();
                },
            }
        }
        span.* = .{
            .start = start,
            .end = end,
        };
    }

    fn parseInteger(self: *Parser) !usize {
        const int_token = try self.consume(.integer);
        return std.fmt.parseUnsigned(usize, self.lexeme(int_token), 10) catch ParserError.IllegalCharacter;
    }

    fn parsePermission(_: *Parser) !void {
        return ParserError.ReservedKeyword;
    }

    fn parseIdentifier(self: *Parser) !ast.Identifier {
        const tok = try self.consume(.identifier);
        const s = try self.intern(self.lexeme(tok));
        return .{
            .symbol = s,
            .span = .{
                .start = tok.start,
                .end = tok.end,
            },
        };
    }

    fn parseValueTypeRef(self: *Parser) !ast.ValueTypeRef {
        const name = try self.parseIdentifier();
        var end = name.span.end;
        var collection = false;
        if (self.match(.l_bracket)) {
            const closing = try self.consume(.r_bracket);
            end = closing.end;
            collection = true;
        } else if (self.match(.r_bracket)) {
            return ParserError.UnexpectedToken;
        }
        return .{
            .name = name,
            .span = .{
                .start = name.span.start,
                .end = end,
            },
            .collection = collection,
        };
    }

    fn skipOpaqueBody(self: *Parser) !ast.Span {
        const opening = try self.consume(.l_brace);
        while (!self.currentIs(.r_brace)) {
            switch (self.current_token.type) {
                .illegal => return ParserError.IllegalCharacter,
                .eof => return ParserError.UnexpectedToken,
                else => self.advance(),
            }
        }
        const closing = try self.consume(.r_brace);

        return .{
            .start = opening.start,
            .end = closing.end,
        };
    }

    // HELPERS
    fn consume(self: *Parser, expected: TokenType) !Token {
        try self.expectCurrent(expected);
        const consumed = self.current_token;
        self.advance();
        return consumed;
    }

    fn match(self: *Parser, expected: TokenType) bool {
        if (!self.currentIs(expected)) {
            return false;
        }
        self.advance();
        return true;
    }

    fn currentIs(self: *Parser, expected: TokenType) bool {
        return self.current_token.type == expected;
    }

    fn expectCurrent(self: *Parser, expected: TokenType) !void {
        if (self.currentIs(.illegal)) {
            return ParserError.IllegalCharacter;
        }
        if (!self.currentIs(expected)) {
            return ParserError.UnexpectedToken;
        }
    }

    fn lexeme(self: *Parser, t: Token) []const u8 {
        return self.lexer.lexeme(t);
    }

    fn intern(self: *Parser, name: []const u8) !SymbolId {
        return self.interner.intern(name);
    }
};

const TestModel = struct {
    parser: Parser,
    model: ast.Model,

    fn parse(source: []const u8) !TestModel {
        const allocator = testing.allocator;
        var parser = Parser.init(allocator, source);
        errdefer parser.deinit();

        const model = try parser.parseModel();
        return .{
            .parser = parser,
            .model = model,
        };
    }

    fn deinit(self: *TestModel) void {
        self.model.deinit(testing.allocator);
        self.parser.deinit();
    }
};

fn expectSpanText(source: []const u8, span: ast.Span, expected: []const u8) !void {
    try testing.expect(span.start <= span.end);
    try testing.expect(span.end <= source.len);
    try testing.expectEqualStrings(expected, source[span.start..span.end]);
}

fn expectExactSpan(source: []const u8, actual: ast.Span, expected_text: []const u8) !void {
    const start = std.mem.indexOf(u8, source, expected_text).?;
    try testing.expectEqual(ast.Span{
        .start = start,
        .end = start + expected_text.len,
    }, actual);
}

fn expectIdentifier(source: []const u8, actual: ast.Identifier, expected: []const u8) !void {
    try expectSpanText(source, actual.span, expected);
}

fn expectRelation(
    source: []const u8,
    actual: ast.Relation,
    expected: struct {
        name: []const u8,
        cardinality: ?ast.Cardinality,
    },
) !void {
    try expectIdentifier(source, actual.name, expected.name);
    try testing.expectEqual(expected.cardinality, actual.cardinality);
}

fn expectParameter(
    source: []const u8,
    actual: ast.Parameter,
    expected: struct {
        name: []const u8,
        type_name: []const u8,
        declaration: []const u8,
        collection: bool = false,
    },
) !void {
    try expectIdentifier(source, actual.name, expected.name);
    try expectIdentifier(source, actual.type.name, expected.type_name);
    try expectSpanText(source, actual.span, expected.declaration);
    const type_start = std.mem.indexOf(u8, expected.declaration, expected.type_name).?;
    try expectSpanText(
        source,
        actual.type.span,
        expected.declaration[type_start..],
    );
    try testing.expectEqual(expected.collection, actual.type.collection);
}

fn expectParseError(expected: anyerror, source: []const u8) !void {
    var parser = Parser.init(testing.allocator, source);
    defer parser.deinit();
    var model = parser.parseModel() catch |err| {
        try testing.expectEqual(expected, err);
        return;
    };
    defer model.deinit(testing.allocator);
    return error.TestUnexpectedResult;
}

test "parse model with simple type" {
    const source = "type User {}";
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 1), parsed.model.types.len);
    try testing.expectEqual(@as(usize, 0), parsed.model.conditions.len);
    try expectIdentifier(source, parsed.model.types[0].name, "User");
    try expectSpanText(source, parsed.model.types[0].span, source);
}

test "parse model with type with body" {
    const source =
        \\type Group {
        \\  relation member[0..10]: User
        \\}
    ;
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 1), parsed.model.types.len);
    try expectIdentifier(source, parsed.model.types[0].name, "Group");
    try expectRelation(source, parsed.model.types[0].relations[0], .{
        .name = "member",
        .cardinality = .{ .min = 0, .max = 10 },
    });
    try expectSpanText(source, parsed.model.types[0].span, source);
}

test "parse model with type with illegal character" {
    try expectParseError(ParserError.IllegalCharacter, "type User { @ }");
}

test "parse model with type missing closing brace" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "type User { relation member[0..10]: User",
    );
}

test "parse model with empty condition" {
    const source = "condition allow() {}";
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 0), parsed.model.types.len);
    try testing.expectEqual(@as(usize, 1), parsed.model.conditions.len);
    const condition = parsed.model.conditions[0];
    try expectIdentifier(source, condition.name, "allow");
    try testing.expectEqual(@as(usize, 0), condition.params.len);
    try expectSpanText(source, condition.span, source);
}

test "parse model with simple condition" {
    const source = "condition allow_ip(ip: IpAddress) {}";
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    const condition = parsed.model.conditions[0];
    try expectIdentifier(source, condition.name, "allow_ip");
    try testing.expectEqual(@as(usize, 1), condition.params.len);
    try expectParameter(source, condition.params[0], .{
        .name = "ip",
        .type_name = "IpAddress",
        .declaration = "ip: IpAddress",
    });
    try expectSpanText(source, condition.span, source);
}

test "parse model with condition with array param" {
    const source = "condition allow_ip(ip: IpAddress[]) {}";
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    const condition = parsed.model.conditions[0];
    try testing.expectEqual(@as(usize, 1), condition.params.len);
    try expectParameter(source, condition.params[0], .{
        .name = "ip",
        .type_name = "IpAddress",
        .declaration = "ip: IpAddress[]",
        .collection = true,
    });
}

test "parse model with condition with multiple params" {
    const source = "condition allow_ip(ip: IpAddress, port: Port) {}";
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    const condition = parsed.model.conditions[0];
    try testing.expectEqual(@as(usize, 2), condition.params.len);
    try expectParameter(source, condition.params[0], .{
        .name = "ip",
        .type_name = "IpAddress",
        .declaration = "ip: IpAddress",
    });
    try expectParameter(source, condition.params[1], .{
        .name = "port",
        .type_name = "Port",
        .declaration = "port: Port",
    });
}

test "parse model with multiple declarations" {
    const source = "type User {} condition allow() {} type Group {}";
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 2), parsed.model.types.len);
    try testing.expectEqual(@as(usize, 1), parsed.model.conditions.len);
    try expectIdentifier(source, parsed.model.types[0].name, "User");
    try expectIdentifier(source, parsed.model.conditions[0].name, "allow");
    try expectIdentifier(source, parsed.model.types[1].name, "Group");
}

test "repeated identifiers share a symbol" {
    const source = "condition allow(subject: User, owner: User) {}";
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    const params = parsed.model.conditions[0].params;
    try testing.expectEqual(@as(usize, 2), params.len);
    try testing.expectEqual(params[0].type.name.symbol, params[1].type.name.symbol);
}

test "declaration spans exclude surrounding source" {
    const source =
        \\  type User {}
        \\  condition allow() {}
        \\  type Group {}
    ;
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    try expectExactSpan(source, parsed.model.types[0].span, "type User {}");
    try expectExactSpan(source, parsed.model.conditions[0].span, "condition allow() {}");
    try expectExactSpan(source, parsed.model.types[1].span, "type Group {}");
}

test "parse model with condition with illegal character" {
    try expectParseError(
        ParserError.IllegalCharacter,
        "condition allow_ip(ip: IpAddress) { @ }",
    );
}

test "parse model with condition missing opening paren" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "condition allow_ip ip: IpAddress {}",
    );
}

test "parse model with condition missing closing paren" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "condition allow_ip(ip: IpAddress {}",
    );
}

test "parse model with condition missing opening brace" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "condition allow_ip(ip: IpAddress)",
    );
}

test "parse model with condition missing closing brace" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "condition allow_ip(ip: IpAddress) {",
    );
}

test "parse model with condition missing opening bracket" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "condition allow_ip(ip: IpAddress]) {}",
    );
}

test "parse model with condition missing closing bracket" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "condition allow_ip(ip: IpAddress[) {}",
    );
}

test "parse model with mixed valid and invalid conditions" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "condition allow_ip(ip: IpAddress) {} condition allow() {",
    );
}

test "parse model with a type with multiple relations" {
    const source =
        \\type Group {
        \\  relation member[0..10]: User
        \\  relation owner: User
        \\}
    ;
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 1), parsed.model.types.len);
    try expectIdentifier(source, parsed.model.types[0].name, "Group");
    try testing.expectEqual(@as(usize, 2), parsed.model.types[0].relations.len);
    try expectRelation(source, parsed.model.types[0].relations[0], .{
        .name = "member",
        .cardinality = .{ .min = 0, .max = 10 },
    });
    try expectRelation(source, parsed.model.types[0].relations[1], .{
        .name = "owner",
        .cardinality = null,
    });
}

test "parse model with a type with relation without upper bound" {
    const source =
        \\type Group {
        \\  relation member[1..]: User
        \\}
    ;
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 1), parsed.model.types.len);
    try expectIdentifier(source, parsed.model.types[0].name, "Group");
    try testing.expectEqual(@as(usize, 1), parsed.model.types[0].relations.len);
    try expectRelation(source, parsed.model.types[0].relations[0], .{
        .name = "member",
        .cardinality = .{ .min = 1, .max = null },
    });
}

test "parse model with a type with relation without lower bound" {
    const source =
        \\type Group {
        \\  relation member[..10]: User
        \\}
    ;
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 1), parsed.model.types.len);
    try expectIdentifier(source, parsed.model.types[0].name, "Group");
    try testing.expectEqual(@as(usize, 1), parsed.model.types[0].relations.len);
    try expectRelation(source, parsed.model.types[0].relations[0], .{
        .name = "member",
        .cardinality = .{ .min = 0, .max = 10 },
    });
}

test "parse a simple model with valid relations" {
    const source =
        \\type User {}
        \\
        \\type Group {
        \\  relation owner: User
        \\  relation member[..10]: User
        \\}
    ;
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    try testing.expectEqual(@as(usize, 2), parsed.model.types.len);
    try expectIdentifier(source, parsed.model.types[0].name, "User");
    try expectIdentifier(source, parsed.model.types[1].name, "Group");
    try testing.expectEqual(@as(usize, 2), parsed.model.types[1].relations.len);
    try expectRelation(source, parsed.model.types[1].relations[0], .{
        .name = "owner",
        .cardinality = null,
    });
    try expectRelation(source, parsed.model.types[1].relations[1], .{
        .name = "member",
        .cardinality = .{ .min = 0, .max = 10 },
    });
}

test "parse model with a type missing opening brace" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "type User }",
    );
}

test "parse model with a type with a relation with missing closing bracket" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "type User { relation member[0..10: User }",
    );
}

test "parse model with a type with a relation with missing opening bracket" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "type User { relation member 0..10]: User }",
    );
}

test "parse model with a type with a relation with missing range token" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "type User { relation member [ 10]: User }",
    );
}

test "parse model with a type with a relation with missing colon" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "type User { relation member[0..10] User }",
    );
}

test "parse model with mixed valid and invalid types" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "type User {} type Group {",
    );
}

test "parse model with a relation with repeated range" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "type User { relation member[0..10..20]: User }",
    );
}

test "parse model with a relation with empty expression" {
    try expectParseError(
        ParserError.UnexpectedToken,
        "type Group { relation member: }",
    );
}

test "parse model with a relation with illegal character in expression" {
    try expectParseError(
        ParserError.IllegalCharacter,
        "type Group { relation member: @ }",
    );
}

test "parse model with a relation with illegal character in declaration" {
    try expectParseError(
        ParserError.IllegalCharacter,
        "type Group { relation member@: User }",
    );
}

test "parse model with a relation with illegal character in cardinality" {
    try expectParseError(
        ParserError.IllegalCharacter,
        "type Group { relation member[0..10@]: User }",
    );
}
