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
        while (!self.currIs(TokenType.eof)) : (self.advance()) {
            switch (self.curr.type) {
                TokenType.kw_type => {
                    const type_decl = try self.parseType();
                    try types.append(self.alloc, type_decl);
                },
                TokenType.kw_condition => {
                    const condition = try self.parseCondition();
                    errdefer condition.deinit(self.alloc);
                    try conditions.append(self.alloc, condition);
                },
                TokenType.illegal => {
                    return ParserError.IllegalCharacter;
                },
                else => {
                    return ParserError.UnexpectedToken;
                },
            }
        }
        return .{
            .types = try types.toOwnedSlice(self.alloc),
            .conditions = try conditions.toOwnedSlice(self.alloc),
        };
    }

    fn parseCondition(self: *Parser) !ast.Condition {
        const start = self.curr.start;
        var end = start;
        self.advance();
        try self.expectCurr(TokenType.identifier);
        const name = try self.parseIdentifier();
        try self.expectCurr(TokenType.l_paren);
        var params: []const ast.Parameter = &.{};
        errdefer self.alloc.free(params);
        self.advance();
        while (!self.currIs(TokenType.r_paren)) : (self.advance()) {
            switch (self.curr.type) {
                TokenType.identifier => {
                    params = try self.parseConditionParams();
                },
                TokenType.illegal => {
                    return ParserError.IllegalCharacter;
                },
                TokenType.eof => {
                    return ParserError.UnexpectedToken;
                },
                else => {
                    return ParserError.UnexpectedToken;
                },
            }
        }
        try self.expectCurr(TokenType.r_paren);
        self.advance();
        try self.expectCurr(TokenType.l_brace);
        self.advance();
        while (!self.currIs(TokenType.r_brace)) : (self.advance()) {
            switch (self.curr.type) {
                TokenType.illegal => {
                    return ParserError.IllegalCharacter;
                },
                TokenType.eof => {
                    return ParserError.UnexpectedToken;
                },
                else => {
                    // TODO: parse condition expressions
                },
            }
        }
        try self.expectCurr(TokenType.r_brace);
        end = self.curr.end;
        return .{
            .name = name,
            .params = params,
            .span = .{
                .start = start,
                .end = end,
            },
        };
    }

    fn parseConditionParams(self: *Parser) ![]const ast.Parameter {
        var params: ArrayList(ast.Parameter) = .empty;
        errdefer params.deinit(self.alloc);
        while (true) {
            const name = try self.parseIdentifier();
            try self.expectCurr(TokenType.colon);
            self.advance(); // skip colon
            const typeRef = try self.parseValueTypeRef();
            try params.append(self.alloc, .{
                .name = name,
                .type = typeRef,
                .span = .{
                    .start = name.span.start,
                    .end = typeRef.span.end,
                },
            });
            if (self.peekIs(TokenType.comma)) { // skip comma
                self.advance();
                self.advance();
            }
            if (self.peekIs(TokenType.r_paren)) {
                break;
            }
        }

        return try params.toOwnedSlice(self.alloc);
    }

    fn parseType(self: *Parser) !ast.Type {
        const start = self.curr.start;
        var end = start;
        self.advance();
        try self.expectCurr(TokenType.identifier);
        const name = try self.parseIdentifier();
        try self.expectCurr(TokenType.l_brace);
        while (true) : (self.advance()) {
            switch (self.curr.type) {
                TokenType.r_brace => {
                    end = self.curr.end;
                    break;
                },
                TokenType.illegal => {
                    return ParserError.IllegalCharacter;
                },
                TokenType.eof => {
                    return ParserError.UnexpectedToken;
                },
                else => {
                    // TODO: parse relations and permissions
                },
            }
        }

        return .{
            .name = name,
            .span = .{
                .start = start,
                .end = end,
            },
        };
    }

    fn parseIdentifier(self: *Parser) !ast.Identifier {
        try self.expectCurr(TokenType.identifier);
        const start = self.curr.start;
        const end = self.curr.end;
        const name = self.currText();
        const s = try self.intern(name);
        self.advance();
        return .{
            .symbol = s,
            .span = .{
                .start = start,
                .end = end,
            },
        };
    }

    fn parseValueTypeRef(self: *Parser) !ast.ValueTypeRef {
        try self.expectCurr(TokenType.identifier);
        const start = self.curr.start;
        const end = self.curr.end;
        const name = self.currText();
        const s = try self.intern(name);
        var collection = false;
        if (self.peekIs(TokenType.l_bracket)) {
            collection = true;
            self.advance();
        }
        if (!collection and self.peekIs(TokenType.r_bracket)) {
            return ParserError.UnexpectedToken;
        }
        if (collection) {
            try self.expectPeek(TokenType.r_bracket);
            self.advance();
        }
        const refEnd = self.curr.end;
        return .{
            .name = .{
                .symbol = s,
                .span = .{
                    .start = start,
                    .end = end,
                },
            },
            .span = .{
                .start = start,
                .end = refEnd,
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

    fn intern(self: *Parser, name: []const u8) !SymbolId {
        return self.i.intern(name);
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
