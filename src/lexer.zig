const token = @import("token.zig");
const Token = token.Token;
const TokenType = token.TokenType;
const std = @import("std");
const testing = std.testing;

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

    pub fn next(self: *Lexer) Token {
        var t: Token = undefined;
        switch (self.ch) {
            0 => {
                t = Token{
                    .type = TokenType.eof,
                    .start = self.pos,
                    .end = self.pos,
                };
            },
            '&', '|', '-', '?', ':', '*', '#', '{', '}', '[', ']', '(', ')' => {
                t = self.readSingleCharToken();
            },
            else => {
                t = Token{
                    .type = TokenType.illegal,
                    .start = self.pos,
                    .end = self.readPos,
                };
            },
        }
        self.readChar();
        return t;
    }
};

test "single character tokens" {
    const input = "&|-?:*#{}[]()";
    var lexer = Lexer.init(input);
    const expected = [_]Token{
        Token{ .type = TokenType.ampersand, .start = 0, .end = 1 },
        Token{ .type = TokenType.pipe, .start = 1, .end = 2 },
        Token{ .type = TokenType.minus, .start = 2, .end = 3 },
        Token{ .type = TokenType.question, .start = 3, .end = 4 },
        Token{ .type = TokenType.colon, .start = 4, .end = 5 },
        Token{ .type = TokenType.star, .start = 5, .end = 6 },
        Token{ .type = TokenType.hash, .start = 6, .end = 7 },
        Token{ .type = TokenType.l_brace, .start = 7, .end = 8 },
        Token{ .type = TokenType.r_brace, .start = 8, .end = 9 },
        Token{ .type = TokenType.l_bracket, .start = 9, .end = 10 },
        Token{ .type = TokenType.r_bracket, .start = 10, .end = 11 },
        Token{ .type = TokenType.l_paren, .start = 11, .end = 12 },
        Token{ .type = TokenType.r_paren, .start = 12, .end = 13 },
    };
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        const t = lexer.next();
        try testing.expectEqual(expected[i].type, t.type);
        try testing.expectEqual(expected[i].start, t.start);
        try testing.expectEqual(expected[i].end, t.end);
    }
}
