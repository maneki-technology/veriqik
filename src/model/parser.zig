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

const Parser = struct {
    allocator: std.mem.Allocator,
    l: Lexer,
    i: Interner,
    curToken: ?Token,
    peekToken: ?Token,
    // TODO: diagnostic/error state

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        var l = Lexer.init(source);
        const i = Interner.init(allocator, std.math.maxInt(u16));
        const curToken = l.next();
        const peekToken = l.next();
        const parser = Parser{
            .allocator = allocator,
            .l = l,
            .i = i,
            .curToken = curToken,
            .peekToken = peekToken,
        };
        return parser;
    }

    pub fn deinit(self: *Parser) void {
        self.i.deinit();
        self.* = undefined;
    }

    fn advance(self: *Parser) void {
        self.curToken = self.peekToken;
        self.peekToken = self.l.next();
    }

    fn parseModel(self: *Parser) !ast.Model {
        var types: ArrayList(ast.Type) = .empty;
        errdefer types.deinit(self.allocator);
        while (self.curToken.?.type != TokenType.eof) : (self.advance()) {
            switch (self.curToken.?.type) {
                TokenType.kw_type => {
                    const type_decl = try self.parseType();
                    try types.append(self.allocator, type_decl);
                },
                TokenType.kw_condition => {},
                TokenType.illegal => {
                    return ParserError.IllegalCharacter;
                },
                else => {
                    return ParserError.UnexpectedToken;
                },
            }
        }
        return .{
            .types = try types.toOwnedSlice(self.allocator),
        };
    }

    fn parseType(self: *Parser) !ast.Type {
        var curToken = self.curToken orelse return ParserError.IllegalCharacter;
        const start = curToken.start;
        var end = start;
        self.advance();
        curToken = self.curToken orelse return ParserError.IllegalCharacter;
        if (curToken.type != TokenType.identifier) {
            return ParserError.UnexpectedToken;
        }
        const nameStart = curToken.start;
        const nameEnd = curToken.end;
        const name = self.l.lexeme(curToken);
        const s = try self.i.intern(name);
        self.advance();
        curToken = self.curToken orelse return ParserError.IllegalCharacter;
        if (curToken.type != TokenType.l_brace) {
            return ParserError.UnexpectedToken;
        }
        while (true) : (self.advance()) {
            curToken = self.curToken orelse return ParserError.IllegalCharacter;
            switch (curToken.type) {
                TokenType.r_brace => {
                    end = curToken.end;
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
            .name = .{
                .symbol = s,
                .span = .{
                    .start = nameStart,
                    .end = nameEnd,
                },
            },
            .span = .{
                .start = start,
                .end = end,
            },
        };
    }
};

fn expectModel(source: []const u8, expected: ast.Model) !void {
    const allocator = std.testing.allocator;
    var parser = Parser.init(allocator, source);
    defer parser.deinit();
    var actual = try parser.parseModel();
    defer actual.deinit(allocator);
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

test "parse model missing closing brace" {
    const source = "type User { relation member[0..10]: User";
    var parser = Parser.init(std.testing.allocator, source);
    defer parser.deinit();
    try testing.expectError(ParserError.UnexpectedToken, parser.parseModel());
}
