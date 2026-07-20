const std = @import("std");
const token = @import("token.zig");
const Token = token.Token;
const TokenType = token.TokenType;

const lexer = @import("lexer.zig");
const Lexer = lexer.Lexer;

const ast = @import("ast.zig");
const ArrayList = std.ArrayList;
const testing = std.testing;

const symbol = @import("symbol.zig");
const SymbolId = symbol.SymbolId;
const Interner = symbol.Interner;

const ParserError = error{
    IllegalCharacter,
    UnexpectedToken,
} || std.mem.Allocator.Error;

pub const Parser = struct {
    alloc: std.mem.Allocator,
    l: Lexer,
    i: Interner,
    curr: Token,
    peek: Token,
    // TODO: diagnostic/error state

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        var l = Lexer.init(source);
        const i = Interner.init(allocator, std.math.maxInt(u16));
        const curr = l.next();
        const peek = l.next();
        const parser = Parser{
            .alloc = allocator,
            .l = l,
            .i = i,
            .curr = curr,
            .peek = peek,
        };
        return parser;
    }

    pub fn deinit(self: *Parser) void {
        self.i.deinit();
        self.* = undefined;
    }

    fn advance(self: *Parser) void {
        self.curr = self.peek;
        self.peek = self.l.next();
    }

    pub fn parseModel(self: *Parser) !ast.Model {
        var types: ArrayList(ast.Type) = .empty;
        errdefer types.deinit(self.alloc);
        var conditions: ArrayList(ast.Condition) = .empty;
        errdefer {
            for (conditions.items) |*cond| {
                cond.deinit(self.alloc);
            }
            conditions.deinit(self.alloc);
        }
        while (!self.currIs(.eof)) {
            switch (self.curr.type) {
                .kw_type => {
                    const type_decl = try self.parseType();
                    // TODO: deinit type_decl
                    try types.append(self.alloc, type_decl);
                },
                .kw_condition => {
                    const condition = try self.parseCondition();
                    errdefer condition.deinit(self.alloc);
                    try conditions.append(self.alloc, condition);
                },
                .illegal => {
                    return ParserError.IllegalCharacter;
                },
                else => {
                    return ParserError.UnexpectedToken;
                },
            }
        }

        const owned_types = try types.toOwnedSlice(self.alloc);
        errdefer self.alloc.free(owned_types);
        const owned_conditions = try conditions.toOwnedSlice(self.alloc);
        errdefer self.alloc.free(owned_conditions);

        return .{
            .types = owned_types,
            .conditions = owned_conditions,
        };
    }

    fn parseCondition(self: *Parser) !ast.Condition {
        const cond = try self.consume(.kw_condition);
        const name = try self.parseIdentifier();
        _ = try self.consume(.l_paren);

        var params: ArrayList(ast.Parameter) = .empty;
        errdefer params.deinit(self.alloc);
        try self.parseConditionParams(&params);
        _ = try self.consume(.r_paren);

        const body = try self.skipOpaqueBody();
        return .{
            .name = name,
            .params = try params.toOwnedSlice(self.alloc),
            .span = .{
                .start = cond.start,
                .end = body.end,
            },
        };
    }

    fn parseConditionParams(self: *Parser, params: *ArrayList(ast.Parameter)) !void {
        if (self.currIs(.r_paren)) return;

        while (true) {
            const param = try self.parseConditionParam();
            try params.append(self.alloc, param);
            if (!self.match(.comma)) break;
        }
    }

    fn parseConditionParam(self: *Parser) !ast.Parameter {
        const name = try self.parseIdentifier();
        _ = try self.consume(.colon);
        const typeRef = try self.parseValueTypeRef();
        return .{
            .name = name,
            .type = typeRef,
            .span = .{
                .start = name.span.start,
                .end = typeRef.span.end,
            },
        };
    }

    fn skipOpaqueBody(self: *Parser) !ast.Span {
        const opening = try self.consume(.l_brace);
        while (!self.currIs(.r_brace)) {
            switch (self.curr.type) {
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

    fn parseType(self: *Parser) !ast.Type {
        const type_decl = try self.consume(.kw_type);
        const name = try self.parseIdentifier();
        const body = try self.skipOpaqueBody();

        return .{
            .name = name,
            .span = .{
                .start = type_decl.start,
                .end = body.end,
            },
        };
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

    // HELPERS
    fn currIs(self: *Parser, expected: TokenType) bool {
        return self.curr.type == expected;
    }

    fn expectCurr(self: *Parser, expected: TokenType) !void {
        if (!self.currIs(expected)) {
            return ParserError.UnexpectedToken;
        }
    }

    fn lexeme(self: *Parser, t: Token) []const u8 {
        return self.l.lexeme(t);
    }

    fn intern(self: *Parser, name: []const u8) !SymbolId {
        return self.i.intern(name);
    }

    fn consume(self: *Parser, expected: TokenType) !Token {
        try self.expectCurr(expected);
        const consumed = self.curr;
        self.advance();
        return consumed;
    }

    fn match(self: *Parser, expected: TokenType) bool {
        if (!self.currIs(expected)) {
            return false;
        }
        self.advance();
        return true;
    }
};

const TestModel = struct {
    parser: Parser,
    model: ast.Model,

    fn parse(source: []const u8) !TestModel {
        const alloc = testing.allocator;
        var parser = Parser.init(alloc, source);
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
    try testing.expectError(expected, parser.parseModel());
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
