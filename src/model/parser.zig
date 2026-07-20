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

    fn peekIs(self: *Parser, expected: TokenType) bool {
        return self.peek.type == expected;
    }

    fn expectCurr(self: *Parser, expected: TokenType) !void {
        if (!self.currIs(expected)) {
            return ParserError.UnexpectedToken;
        }
    }

    fn expectPeek(self: *Parser, expected: TokenType) !void {
        if (!self.peekIs(expected)) {
            return ParserError.UnexpectedToken;
        }
    }

    fn currText(self: *Parser) []const u8 {
        return self.l.lexeme(self.curr);
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

fn expectModel(source: []const u8, expected: ast.Model) !void {
    const alloc = std.testing.allocator;
    var parser = Parser.init(alloc, source);
    defer parser.deinit();
    var actual = try parser.parseModel();
    defer actual.deinit(alloc);
    try testing.expectEqualDeep(expected, actual);
}

test "parse model with simple type" {
    const source = "type User {}";
    const expected = ast.Model{
        .types = &[_]ast.Type{
            .{
                .name = .{
                    .symbol = SymbolId.fromInt(0),
                    .span = .{ .start = 5, .end = 9 },
                },
                .span = .{ .start = 0, .end = source.len },
            },
        },
    };

    try expectModel(source, expected);
}

test "parse model with type with body" {
    const source =
        \\type Group {
        \\  relation member[0..10]: User
        \\}
    ;
    const expected = ast.Model{
        .types = &[_]ast.Type{
            .{
                .name = .{
                    .symbol = SymbolId.fromInt(0),
                    .span = .{ .start = 5, .end = 10 },
                },
                .span = .{ .start = 0, .end = source.len },
            },
        },
    };

    try expectModel(source, expected);
}

test "parse model with type with illegal character" {
    const source = "type User { @ }";
    var parser = Parser.init(std.testing.allocator, source);
    defer parser.deinit();
    try testing.expectError(ParserError.IllegalCharacter, parser.parseModel());
}

test "parse model with type missing closing brace" {
    const source = "type User { relation member[0..10]: User";
    var parser = Parser.init(std.testing.allocator, source);
    defer parser.deinit();
    try testing.expectError(ParserError.UnexpectedToken, parser.parseModel());
}

test "parse model with empty condition" {
    const source = "condition allow() {}";
    const expected = ast.Model{
        .types = &.{},
        .conditions = &[_]ast.Condition{
            .{
                .name = .{
                    .symbol = SymbolId.fromInt(0),
                    .span = .{ .start = 10, .end = 15 },
                },
                .params = &.{},
                .span = .{ .start = 0, .end = source.len },
            },
        },
    };

    try expectModel(source, expected);
}

test "parse model with simple condition" {
    const source = "condition allow_ip(ip: IpAddress) {}";
    const expected = ast.Model{
        .types = &.{},
        .conditions = &[_]ast.Condition{
            .{
                .name = .{
                    .symbol = SymbolId.fromInt(0),
                    .span = .{ .start = 10, .end = 18 },
                },
                .params = &.{
                    .{
                        .name = .{
                            .symbol = SymbolId.fromInt(1),
                            .span = .{ .start = 19, .end = 21 },
                        },
                        .type = .{
                            .name = .{
                                .symbol = SymbolId.fromInt(2),
                                .span = .{ .start = 23, .end = 32 },
                            },
                            .span = .{ .start = 23, .end = 32 },
                            .collection = false,
                        },
                        .span = .{ .start = 19, .end = 32 },
                    },
                },
                .span = .{ .start = 0, .end = source.len },
            },
        },
    };

    try expectModel(source, expected);
}

test "parse model with condition with array param" {
    const source = "condition allow_ip(ip: IpAddress[]) {}";
    const expected = ast.Model{
        .types = &.{},
        .conditions = &[_]ast.Condition{
            .{
                .name = .{
                    .symbol = SymbolId.fromInt(0),
                    .span = .{ .start = 10, .end = 18 },
                },
                .params = &.{
                    .{
                        .name = .{
                            .symbol = SymbolId.fromInt(1),
                            .span = .{ .start = 19, .end = 21 },
                        },
                        .type = .{
                            .name = .{
                                .symbol = SymbolId.fromInt(2),
                                .span = .{ .start = 23, .end = 32 },
                            },
                            .span = .{ .start = 23, .end = 34 },
                            .collection = true,
                        },
                        .span = .{ .start = 19, .end = 34 },
                    },
                },
                .span = .{ .start = 0, .end = source.len },
            },
        },
    };

    try expectModel(source, expected);
}

test "parse model with condition with multiple params" {
    const source = "condition allow_ip(ip: IpAddress, port: Port) {}";
    const expected = ast.Model{
        .types = &.{},
        .conditions = &[_]ast.Condition{
            .{
                .name = .{
                    .symbol = SymbolId.fromInt(0),
                    .span = .{ .start = 10, .end = 18 },
                },
                .params = &.{
                    .{
                        .name = .{
                            .symbol = SymbolId.fromInt(1),
                            .span = .{ .start = 19, .end = 21 },
                        },
                        .type = .{
                            .name = .{
                                .symbol = SymbolId.fromInt(2),
                                .span = .{ .start = 23, .end = 32 },
                            },
                            .span = .{ .start = 23, .end = 32 },
                            .collection = false,
                        },
                        .span = .{ .start = 19, .end = 32 },
                    },
                    .{
                        .name = .{
                            .symbol = SymbolId.fromInt(3),
                            .span = .{ .start = 34, .end = 38 },
                        },
                        .type = .{
                            .name = .{
                                .symbol = SymbolId.fromInt(4),
                                .span = .{ .start = 40, .end = 44 },
                            },
                            .span = .{ .start = 40, .end = 44 },
                            .collection = false,
                        },
                        .span = .{ .start = 34, .end = 44 },
                    },
                },
                .span = .{ .start = 0, .end = source.len },
            },
        },
    };

    try expectModel(source, expected);
}

test "parse model with conditon with illegal character" {
    const source = "condition allow_ip(ip: IpAddress) { @ }";
    var parser = Parser.init(std.testing.allocator, source);
    defer parser.deinit();
    try testing.expectError(ParserError.IllegalCharacter, parser.parseModel());
}

test "parse model with condition missing opening paren" {
    const source = "condition allow_ip ip: IpAddress {}";
    var parser = Parser.init(std.testing.allocator, source);
    defer parser.deinit();
    try testing.expectError(ParserError.UnexpectedToken, parser.parseModel());
}

test "parse model with condition missing closing paren" {
    const source = "condition allow_ip(ip: IpAddress {}";
    var parser = Parser.init(std.testing.allocator, source);
    defer parser.deinit();
    try testing.expectError(ParserError.UnexpectedToken, parser.parseModel());
}

test "parse model with condition missing opening brace" {
    const source = "condition allow_ip(ip: IpAddress)";
    var parser = Parser.init(std.testing.allocator, source);
    defer parser.deinit();
    try testing.expectError(ParserError.UnexpectedToken, parser.parseModel());
}

test "parse model with condition missing closing brace" {
    const source = "condition allow_ip(ip: IpAddress) {";
    var parser = Parser.init(std.testing.allocator, source);
    defer parser.deinit();
    try testing.expectError(ParserError.UnexpectedToken, parser.parseModel());
}

test "parse model with condition missing opening bracket" {
    const source = "condition allow_ip(ip: IpAddress]) {}";
    var parser = Parser.init(std.testing.allocator, source);
    defer parser.deinit();
    try testing.expectError(ParserError.UnexpectedToken, parser.parseModel());
}

test "parse model with condition missing closing bracket" {
    const source = "condition allow_ip(ip: IpAddress[) {}";
    var parser = Parser.init(std.testing.allocator, source);
    defer parser.deinit();
    try testing.expectError(ParserError.UnexpectedToken, parser.parseModel());
}
