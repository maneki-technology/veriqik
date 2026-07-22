const std = @import("std");
const token_module = @import("token.zig");
const Token = token_module.Token;
const TokenType = token_module.TokenType;

const lexer_module = @import("lexer.zig");
const Lexer = lexer_module.Lexer;

const ast = @import("ast.zig");
const ArrayList = std.ArrayList;
const testing = std.testing;

const symbol_module = @import("symbol.zig");
const SymbolId = symbol_module.SymbolId;
const Interner = symbol_module.Interner;

const ParserError = error{
    IllegalCharacter,
    UnexpectedToken,
    ReservedKeyword,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: Lexer,
    interner: Interner,
    token_current: Token,
    token_peek: Token,
    // TODO: diagnostic/error state

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        var lexer = Lexer.init(source);
        const interner = Interner.init(allocator, std.math.maxInt(u16));
        const token_current = lexer.next();
        const token_peek = lexer.next();
        return .{
            .allocator = allocator,
            .lexer = lexer,
            .interner = interner,
            .token_current = token_current,
            .token_peek = token_peek,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.interner.deinit();
        self.* = undefined;
    }

    fn advance(self: *Parser) void {
        self.token_current = self.token_peek;
        self.token_peek = self.lexer.next();
    }

    pub fn parse_model(self: *Parser) !ast.Model {
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

        while (!self.current_token_is(.eof)) {
            switch (self.token_current.type) {
                .kw_type => {
                    const type_decl = try self.parse_type();
                    errdefer type_decl.deinit(self.allocator);
                    try types.append(self.allocator, type_decl);
                },
                .kw_condition => {
                    const condition = try self.parse_condition();
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
            self.allocator.free(owned_conditions);
        }

        return .{
            .types = owned_types,
            .conditions = owned_conditions,
        };
    }

    fn parse_condition(self: *Parser) !ast.Condition {
        const condition = try self.consume(.kw_condition);
        const name = try self.parse_identifier();
        _ = try self.consume(.l_paren);

        var params: ArrayList(ast.Parameter) = .empty;
        errdefer params.deinit(self.allocator);
        try self.parse_condition_params(&params);
        _ = try self.consume(.r_paren);

        const body = try self.skip_opaque_body();
        return .{
            .name = name,
            .params = try params.toOwnedSlice(self.allocator),
            .span = .{
                .start = condition.start,
                .end = body.end,
            },
        };
    }

    fn parse_condition_params(self: *Parser, params: *ArrayList(ast.Parameter)) !void {
        if (self.current_token_is(.r_paren)) return;

        while (true) {
            const param = try self.parse_condition_param();
            try params.append(self.allocator, param);
            if (!self.match(.comma)) break;
        }
    }

    fn parse_condition_param(self: *Parser) !ast.Parameter {
        const name = try self.parse_identifier();
        _ = try self.consume(.colon);
        const type_ref = try self.parse_value_type_ref();
        return .{
            .name = name,
            .type = type_ref,
            .span = .{
                .start = name.span.start,
                .end = type_ref.span.end,
            },
        };
    }

    fn parse_type(self: *Parser) !ast.Type {
        const type_decl = try self.consume(.kw_type);
        const name = try self.parse_identifier();
        var body_span: ast.Span = undefined;
        var relations: ArrayList(ast.Relation) = .empty;
        errdefer relations.deinit(self.allocator);
        try self.parse_type_body(&body_span, &relations);

        const owned_relations = try relations.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(owned_relations);

        return .{
            .name = name,
            .relations = owned_relations,
            .span = .{
                .start = type_decl.start,
                .end = body_span.end,
            },
        };
    }

    fn parse_type_body(self: *Parser, span: *ast.Span, relations: *ArrayList(ast.Relation)) !void {
        const opening = try self.consume(.l_brace);
        while (!self.current_token_is(.r_brace)) {
            switch (self.token_current.type) {
                .kw_relation => try self.parse_relation(relations),
                .kw_permission => try self.parse_permission(),
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

    fn parse_relation(self: *Parser, relations: *ArrayList(ast.Relation)) !void {
        const relation_decl = try self.consume(.kw_relation);
        const name = try self.parse_identifier();
        var cardinality: ?ast.Cardinality = null;
        if (self.match(.l_bracket)) {
            cardinality = .{ .max = null };
            switch (self.token_current.type) {
                .range => {
                    _ = try self.consume(.range);
                    if (self.current_token_is(.integer)) {
                        cardinality.?.max = try self.parse_integer();
                    }
                    _ = try self.consume(.r_bracket);
                },
                .integer => {
                    cardinality.?.min = try self.parse_integer();
                    _ = try self.consume(.range);
                    if (self.current_token_is(.integer)) {
                        cardinality.?.max = try self.parse_integer();
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
        try self.skip_relation_expression(&expr_span);
        try relations.append(self.allocator, .{
            .name = name,
            .cardinality = cardinality,
            .span = .{
                .start = relation_decl.start,
                .end = expr_span.end,
            },
        });
    }

    fn skip_relation_expression(self: *Parser, span: *ast.Span) !void {
        // Empty expression
        if (self.current_token_is(.kw_relation) or
            self.current_token_is(.kw_permission) or
            self.current_token_is(.r_brace) or
            self.current_token_is(.eof))
        {
            return ParserError.UnexpectedToken;
        }

        const start = self.token_current.start;
        var end = self.token_current.end;
        while (true) {
            switch (self.token_current.type) {
                .kw_relation, .kw_permission, .r_brace, .eof => break,
                .illegal => return ParserError.IllegalCharacter,
                else => {
                    end = self.token_current.end;
                    self.advance();
                },
            }
        }
        span.* = .{
            .start = start,
            .end = end,
        };
    }

    fn parse_integer(self: *Parser) !usize {
        const int_token = try self.consume(.integer);
        return std.fmt.parseUnsigned(usize, self.lexeme(int_token), 10) catch ParserError.IllegalCharacter;
    }

    fn parse_permission(_: *Parser) !void {
        return ParserError.ReservedKeyword;
    }

    fn parse_identifier(self: *Parser) !ast.Identifier {
        const identifier = try self.consume(.identifier);
        const symbol = try self.intern(self.lexeme(identifier));
        return .{
            .symbol = symbol,
            .span = .{
                .start = identifier.start,
                .end = identifier.end,
            },
        };
    }

    fn parse_value_type_ref(self: *Parser) !ast.ValueTypeRef {
        const name = try self.parse_identifier();
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

    fn skip_opaque_body(self: *Parser) !ast.Span {
        const opening = try self.consume(.l_brace);
        while (!self.current_token_is(.r_brace)) {
            switch (self.token_current.type) {
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
        try self.expect_current_token(expected);
        const consumed = self.token_current;
        self.advance();
        return consumed;
    }

    fn match(self: *Parser, expected: TokenType) bool {
        if (!self.current_token_is(expected)) {
            return false;
        }
        self.advance();
        return true;
    }

    fn current_token_is(self: *Parser, expected: TokenType) bool {
        return self.token_current.type == expected;
    }

    fn expect_current_token(self: *Parser, expected: TokenType) !void {
        if (self.current_token_is(.illegal)) {
            return ParserError.IllegalCharacter;
        }
        if (!self.current_token_is(expected)) {
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

        const model = try parser.parse_model();
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

fn expect_span_text(source: []const u8, span: ast.Span, expected: []const u8) !void {
    try testing.expect(span.start <= span.end);
    try testing.expect(span.end <= source.len);
    try testing.expectEqualStrings(expected, source[span.start..span.end]);
}

fn expect_exact_span(source: []const u8, actual: ast.Span, expected_text: []const u8) !void {
    const start = std.mem.indexOf(u8, source, expected_text).?;
    try testing.expectEqual(ast.Span{
        .start = start,
        .end = start + expected_text.len,
    }, actual);
}

fn expect_identifier(source: []const u8, actual: ast.Identifier, expected: []const u8) !void {
    try expect_span_text(source, actual.span, expected);
}

fn expect_relation(
    source: []const u8,
    actual: ast.Relation,
    expected: struct {
        name: []const u8,
        cardinality: ?ast.Cardinality,
    },
) !void {
    try expect_identifier(source, actual.name, expected.name);
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
    try expect_identifier(source, actual.name, expected.name);
    try expect_identifier(source, actual.type.name, expected.type_name);
    try expect_span_text(source, actual.span, expected.declaration);
    const type_start = std.mem.indexOf(u8, expected.declaration, expected.type_name).?;
    try expect_span_text(
        source,
        actual.type.span,
        expected.declaration[type_start..],
    );
    try testing.expectEqual(expected.collection, actual.type.collection);
}

fn expect_parse_error(expected: anyerror, source: []const u8) !void {
    var parser = Parser.init(testing.allocator, source);
    defer parser.deinit();
    var model = parser.parse_model() catch |err| {
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
    try expect_identifier(source, parsed.model.types[0].name, "User");
    try expect_span_text(source, parsed.model.types[0].span, source);
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
    try expect_identifier(source, parsed.model.types[0].name, "Group");
    try expect_relation(source, parsed.model.types[0].relations[0], .{
        .name = "member",
        .cardinality = .{ .min = 0, .max = 10 },
    });
    try expect_span_text(source, parsed.model.types[0].span, source);
}

test "parse model with type with illegal character" {
    try expect_parse_error(ParserError.IllegalCharacter, "type User { @ }");
}

test "parse model with type missing closing brace" {
    try expect_parse_error(
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
    try expect_identifier(source, condition.name, "allow");
    try testing.expectEqual(@as(usize, 0), condition.params.len);
    try expect_span_text(source, condition.span, source);
}

test "parse model with simple condition" {
    const source = "condition allow_ip(ip: IpAddress) {}";
    var parsed = try TestModel.parse(source);
    defer parsed.deinit();

    const condition = parsed.model.conditions[0];
    try expect_identifier(source, condition.name, "allow_ip");
    try testing.expectEqual(@as(usize, 1), condition.params.len);
    try expectParameter(source, condition.params[0], .{
        .name = "ip",
        .type_name = "IpAddress",
        .declaration = "ip: IpAddress",
    });
    try expect_span_text(source, condition.span, source);
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
    try expect_identifier(source, parsed.model.types[0].name, "User");
    try expect_identifier(source, parsed.model.conditions[0].name, "allow");
    try expect_identifier(source, parsed.model.types[1].name, "Group");
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

    try expect_exact_span(source, parsed.model.types[0].span, "type User {}");
    try expect_exact_span(source, parsed.model.conditions[0].span, "condition allow() {}");
    try expect_exact_span(source, parsed.model.types[1].span, "type Group {}");
}

test "parse model with condition with illegal character" {
    try expect_parse_error(
        ParserError.IllegalCharacter,
        "condition allow_ip(ip: IpAddress) { @ }",
    );
}

test "parse model with condition missing opening paren" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "condition allow_ip ip: IpAddress {}",
    );
}

test "parse model with condition missing closing paren" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "condition allow_ip(ip: IpAddress {}",
    );
}

test "parse model with condition missing opening brace" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "condition allow_ip(ip: IpAddress)",
    );
}

test "parse model with condition missing closing brace" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "condition allow_ip(ip: IpAddress) {",
    );
}

test "parse model with condition missing opening bracket" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "condition allow_ip(ip: IpAddress]) {}",
    );
}

test "parse model with condition missing closing bracket" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "condition allow_ip(ip: IpAddress[) {}",
    );
}

test "parse model with mixed valid and invalid conditions" {
    try expect_parse_error(
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
    try expect_identifier(source, parsed.model.types[0].name, "Group");
    try testing.expectEqual(@as(usize, 2), parsed.model.types[0].relations.len);
    try expect_relation(source, parsed.model.types[0].relations[0], .{
        .name = "member",
        .cardinality = .{ .min = 0, .max = 10 },
    });
    try expect_relation(source, parsed.model.types[0].relations[1], .{
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
    try expect_identifier(source, parsed.model.types[0].name, "Group");
    try testing.expectEqual(@as(usize, 1), parsed.model.types[0].relations.len);
    try expect_relation(source, parsed.model.types[0].relations[0], .{
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
    try expect_identifier(source, parsed.model.types[0].name, "Group");
    try testing.expectEqual(@as(usize, 1), parsed.model.types[0].relations.len);
    try expect_relation(source, parsed.model.types[0].relations[0], .{
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
    try expect_identifier(source, parsed.model.types[0].name, "User");
    try expect_identifier(source, parsed.model.types[1].name, "Group");
    try testing.expectEqual(@as(usize, 2), parsed.model.types[1].relations.len);
    try expect_relation(source, parsed.model.types[1].relations[0], .{
        .name = "owner",
        .cardinality = null,
    });
    try expect_relation(source, parsed.model.types[1].relations[1], .{
        .name = "member",
        .cardinality = .{ .min = 0, .max = 10 },
    });
}

test "parse model with a type missing opening brace" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "type User }",
    );
}

test "parse model with a type with a relation with missing closing bracket" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "type User { relation member[0..10: User }",
    );
}

test "parse model with a type with a relation with missing opening bracket" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "type User { relation member 0..10]: User }",
    );
}

test "parse model with a type with a relation with missing range token" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "type User { relation member [ 10]: User }",
    );
}

test "parse model with a type with a relation with missing colon" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "type User { relation member[0..10] User }",
    );
}

test "parse model with mixed valid and invalid types" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "type User {} type Group {",
    );
}

test "parse model with a relation with repeated range" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "type User { relation member[0..10..20]: User }",
    );
}

test "parse model with a relation with empty expression" {
    try expect_parse_error(
        ParserError.UnexpectedToken,
        "type Group { relation member: }",
    );
}

test "parse model with a relation with illegal character in expression" {
    try expect_parse_error(
        ParserError.IllegalCharacter,
        "type Group { relation member: @ }",
    );
}

test "parse model with a relation with illegal character in declaration" {
    try expect_parse_error(
        ParserError.IllegalCharacter,
        "type Group { relation member@: User }",
    );
}

test "parse model with a relation with illegal character in cardinality" {
    try expect_parse_error(
        ParserError.IllegalCharacter,
        "type Group { relation member[0..10@]: User }",
    );
}
