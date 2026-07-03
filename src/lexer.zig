const token = @import("token.zig");
const Token = token.Token;
const TokenType = token.TokenType;
const std = @import("std");
const testing = std.testing;

const keywords = std.StaticStringMap(TokenType).initComptime(.{
    .{ "type", TokenType.kw_type },
    .{ "relation", TokenType.kw_relation },
    .{ "permission", TokenType.kw_permission },
    .{ "condition", TokenType.kw_condition },
    .{ "with", TokenType.kw_with },
    .{ "in", TokenType.kw_in },
    .{ "self", TokenType.kw_self },
    .{ "resource", TokenType.kw_resource },
});

pub const Lexer = struct {
    input: []const u8,
    pos: usize,
    readPos: usize,
    ch: u8,

    fn readChar(self: *Lexer) void {
        self.pos = self.readPos;
        if (self.readPos >= self.input.len) {
            self.ch = 0;
            return;
        }
        self.ch = self.input[self.readPos];
        self.readPos += 1;
    }

    pub fn init(input: []const u8) Lexer {
        var lexer = Lexer{
            .input = input,
            .pos = 0,
            .readPos = 0,
            .ch = 0,
        };

        lexer.readChar();
        return lexer;
    }

    fn readSingleCharToken(self: *Lexer) Token {
        var t = Token{
            .type = TokenType.illegal,
            .start = self.pos,
            .end = self.readPos,
        };
        switch (self.ch) {
            '&' => {
                t.type = TokenType.ampersand;
            },
            '|' => {
                t.type = TokenType.pipe;
            },
            '-' => {
                t.type = TokenType.minus;
            },
            '?' => {
                t.type = TokenType.question;
            },
            ':' => {
                t.type = TokenType.colon;
            },
            ',' => {
                t.type = TokenType.comma;
            },
            '*' => {
                t.type = TokenType.star;
            },
            '#' => {
                t.type = TokenType.hash;
            },
            '{' => {
                t.type = TokenType.l_brace;
            },
            '}' => {
                t.type = TokenType.r_brace;
            },
            '[' => {
                t.type = TokenType.l_bracket;
            },
            ']' => {
                t.type = TokenType.r_bracket;
            },
            '(' => {
                t.type = TokenType.l_paren;
            },
            ')' => {
                t.type = TokenType.r_paren;
            },
            else => {},
        }
        return t;
    }

    fn peek(self: *Lexer) u8 {
        if (self.readPos >= self.input.len) {
            return 0;
        }
        return self.input[self.readPos];
    }

    fn isWhitespace(self: *Lexer) bool {
        return self.ch == ' ' or self.ch == '\t' or self.ch == '\n' or self.ch == '\r';
    }

    fn eatWhitespace(self: *Lexer) void {
        while (self.isWhitespace()) {
            self.readChar();
        }
    }

    fn readLookaheadCharToken(self: *Lexer) Token {
        var t = Token{
            .type = TokenType.illegal,
            .start = self.pos,
            .end = self.readPos,
        };
        const nextCh = self.peek();
        switch (self.ch) {
            '=' => {
                if (nextCh == '=') {
                    t.type = TokenType.equal_equal;
                    t.end = self.readPos + 1;
                    self.readChar();
                } else {
                    t.type = TokenType.assign;
                    return t;
                }
            },
            '<' => {
                if (nextCh == '=') {
                    t.type = TokenType.less_equal;
                    t.end = self.readPos + 1;
                    self.readChar();
                } else {
                    t.type = TokenType.less;
                    return t;
                }
            },
            '>' => {
                if (nextCh == '=') {
                    t.type = TokenType.greater_equal;
                    t.end = self.readPos + 1;
                    self.readChar();
                } else {
                    t.type = TokenType.greater;
                    return t;
                }
            },
            '!' => {
                if (nextCh == '=') {
                    t.type = TokenType.bang_equal;
                    t.end = self.readPos + 1;
                    self.readChar();
                } else {
                    t.type = TokenType.bang;
                    return t;
                }
            },
            '.' => {
                if (nextCh == '.') {
                    t.type = TokenType.range;
                    t.end = self.readPos + 1;
                    self.readChar();
                } else {
                    t.type = TokenType.dot;
                    return t;
                }
            },
            else => {},
        }
        return t;
    }

    fn isAlpha(self: *Lexer) bool {
        return (self.ch >= 'a' and self.ch <= 'z') or (self.ch >= 'A' and self.ch <= 'Z');
    }

    fn readIdentifierToken(self: *Lexer) Token {
        var t = Token{ .type = TokenType.identifier, .start = self.pos, .end = self.pos };
        while (self.isAlpha()) {
            self.readChar();
        }
        t.end = self.pos;
        if (keywords.get(self.input[t.start..t.end])) |kw| {
            t.type = kw;
        }
        return t;
    }

    pub fn next(self: *Lexer) Token {
        self.eatWhitespace();
        var t = Token{
            .type = TokenType.illegal,
            .start = self.pos,
            .end = self.readPos,
        };
        switch (self.ch) {
            0 => {
                t.type = TokenType.eof;
                t.end = self.pos;
            },
            '&', '|', '-', '?', ':', ',', '*', '#', '{', '}', '[', ']', '(', ')' => {
                t = self.readSingleCharToken();
            },
            '=', '<', '>', '!', '.' => {
                t = self.readLookaheadCharToken();
            },
            else => {
                if (self.isAlpha()) {
                    t = self.readIdentifierToken();
                    return t;
                }
            },
        }
        self.readChar();
        return t;
    }
};

test "single character tokens" {
    const input = "&|-?:,*#{}[]()";
    var lexer = Lexer.init(input);
    const expected = [_]Token{
        Token{ .type = TokenType.ampersand, .start = 0, .end = 1 },
        Token{ .type = TokenType.pipe, .start = 1, .end = 2 },
        Token{ .type = TokenType.minus, .start = 2, .end = 3 },
        Token{ .type = TokenType.question, .start = 3, .end = 4 },
        Token{ .type = TokenType.colon, .start = 4, .end = 5 },
        Token{ .type = TokenType.comma, .start = 5, .end = 6 },
        Token{ .type = TokenType.star, .start = 6, .end = 7 },
        Token{ .type = TokenType.hash, .start = 7, .end = 8 },
        Token{ .type = TokenType.l_brace, .start = 8, .end = 9 },
        Token{ .type = TokenType.r_brace, .start = 9, .end = 10 },
        Token{ .type = TokenType.l_bracket, .start = 10, .end = 11 },
        Token{ .type = TokenType.r_bracket, .start = 11, .end = 12 },
        Token{ .type = TokenType.l_paren, .start = 12, .end = 13 },
        Token{ .type = TokenType.r_paren, .start = 13, .end = 14 },
        Token{ .type = TokenType.eof, .start = 14, .end = 14 },
    };
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        const t = lexer.next();
        try testing.expectEqual(expected[i].type, t.type);
        try testing.expectEqual(expected[i].start, t.start);
        try testing.expectEqual(expected[i].end, t.end);
    }
}

test "lookahead tokens" {
    const input = "= < > == <= >= != .. .!";
    var lexer = Lexer.init(input);
    const expected = [_]Token{
        Token{ .type = TokenType.assign, .start = 0, .end = 1 },
        Token{ .type = TokenType.less, .start = 2, .end = 3 },
        Token{ .type = TokenType.greater, .start = 4, .end = 5 },
        Token{ .type = TokenType.equal_equal, .start = 6, .end = 8 },
        Token{ .type = TokenType.less_equal, .start = 9, .end = 11 },
        Token{ .type = TokenType.greater_equal, .start = 12, .end = 14 },
        Token{ .type = TokenType.bang_equal, .start = 15, .end = 17 },
        Token{ .type = TokenType.range, .start = 18, .end = 20 },
        Token{ .type = TokenType.dot, .start = 21, .end = 22 },
        Token{ .type = TokenType.bang, .start = 22, .end = 23 },
        Token{ .type = TokenType.eof, .start = 23, .end = 23 },
    };
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        const t = lexer.next();
        try testing.expectEqual(expected[i].type, t.type);
        try testing.expectEqual(expected[i].start, t.start);
        try testing.expectEqual(expected[i].end, t.end);
    }
}

test "lookahead tokens same first char consecutive" {
    const input = "= == . .. == = .. .";
    var lexer = Lexer.init(input);
    const expected = [_]Token{
        Token{ .type = TokenType.assign, .start = 0, .end = 1 },
        Token{ .type = TokenType.equal_equal, .start = 2, .end = 4 },
        Token{ .type = TokenType.dot, .start = 5, .end = 6 },
        Token{ .type = TokenType.range, .start = 7, .end = 9 },
        Token{ .type = TokenType.equal_equal, .start = 10, .end = 12 },
        Token{ .type = TokenType.assign, .start = 13, .end = 14 },
        Token{ .type = TokenType.range, .start = 15, .end = 17 },
        Token{ .type = TokenType.dot, .start = 18, .end = 19 },
        Token{ .type = TokenType.eof, .start = 19, .end = 19 },
    };
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        const t = lexer.next();
        try testing.expectEqual(expected[i].type, t.type);
        try testing.expectEqual(expected[i].start, t.start);
        try testing.expectEqual(expected[i].end, t.end);
    }
}

test "keywords" {
    const input = "type relation permission condition with in self resource";
    var lexer = Lexer.init(input);
    const expected = [_]Token{
        Token{ .type = TokenType.kw_type, .start = 0, .end = 4 },
        Token{ .type = TokenType.kw_relation, .start = 5, .end = 13 },
        Token{ .type = TokenType.kw_permission, .start = 14, .end = 24 },
        Token{ .type = TokenType.kw_condition, .start = 25, .end = 34 },
        Token{ .type = TokenType.kw_with, .start = 35, .end = 39 },
        Token{ .type = TokenType.kw_in, .start = 40, .end = 42 },
        Token{ .type = TokenType.kw_self, .start = 43, .end = 47 },
        Token{ .type = TokenType.kw_resource, .start = 48, .end = 56 },
        Token{ .type = TokenType.eof, .start = 56, .end = 56 },
    };
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        const t = lexer.next();
        try testing.expectEqual(expected[i].type, t.type);
        try testing.expectEqual(expected[i].start, t.start);
        try testing.expectEqual(expected[i].end, t.end);
    }
}

test "identifiers" {
    const input = "foo bar baz";
    var lexer = Lexer.init(input);
    const expected = [_]Token{
        Token{ .type = TokenType.identifier, .start = 0, .end = 3 },
        Token{ .type = TokenType.identifier, .start = 4, .end = 7 },
        Token{ .type = TokenType.identifier, .start = 8, .end = 11 },
        Token{ .type = TokenType.eof, .start = 11, .end = 11 },
    };
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        const t = lexer.next();
        try testing.expectEqual(expected[i].type, t.type);
        try testing.expectEqual(expected[i].start, t.start);
        try testing.expectEqual(expected[i].end, t.end);
    }
}

test "simple type" {
    const input =
        \\type Team {
        \\    relation member: User
        \\    permission members = member
        \\}
    ;
    var lexer = Lexer.init(input);
    const expected = [_]Token{
        Token{ .type = TokenType.kw_type, .start = 0, .end = 4 },
        Token{ .type = TokenType.identifier, .start = 5, .end = 9 },
        Token{ .type = TokenType.l_brace, .start = 10, .end = 11 },
        Token{ .type = TokenType.kw_relation, .start = 16, .end = 24 },
        Token{ .type = TokenType.identifier, .start = 25, .end = 31 },
        Token{ .type = TokenType.colon, .start = 31, .end = 32 },
        Token{ .type = TokenType.identifier, .start = 33, .end = 37 },
        Token{ .type = TokenType.kw_permission, .start = 42, .end = 52 },
        Token{ .type = TokenType.identifier, .start = 53, .end = 60 },
        Token{ .type = TokenType.assign, .start = 61, .end = 62 },
        Token{ .type = TokenType.identifier, .start = 63, .end = 69 },
        Token{ .type = TokenType.r_brace, .start = 70, .end = 71 },
        Token{ .type = TokenType.eof, .start = 71, .end = 71 },
    };
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        const t = lexer.next();
        try testing.expectEqual(expected[i].type, t.type);
        try testing.expectEqual(expected[i].start, t.start);
        try testing.expectEqual(expected[i].end, t.end);
    }
}
