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
});

pub const Lexer = struct {
    input: []const u8,
    pos: usize,

    pub fn init(input: []const u8) Lexer {
        const lexer = Lexer{
            .input = input,
            .pos = 0,
        };

        return lexer;
    }

    fn isAtEnd(self: *Lexer) bool {
        return self.pos >= self.input.len;
    }

    fn current(self: *Lexer) u8 {
        if (self.isAtEnd()) {
            return 0;
        }
        return self.input[self.pos];
    }

    fn advance(self: *Lexer) void {
        if (self.isAtEnd()) {
            return;
        }
        self.pos += 1;
    }

    fn readSingleCharToken(self: *Lexer) Token {
        var t = Token{
            .type = TokenType.illegal,
            .start = self.pos,
            .end = self.pos + 1,
        };
        switch (self.current()) {
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
        if (self.pos + 1 >= self.input.len) {
            return 0;
        }
        return self.input[self.pos + 1];
    }

    fn readLookaheadCharToken(self: *Lexer) Token {
        var t = Token{
            .type = TokenType.illegal,
            .start = self.pos,
            .end = self.pos + 1,
        };
        switch (self.current()) {
            '=' => {
                if (self.peek() == '=') {
                    t.type = TokenType.equal_equal;
                    t.end = self.pos + 2;
                    self.advance();
                } else {
                    t.type = TokenType.assign;
                    return t;
                }
            },
            '<' => {
                if (self.peek() == '=') {
                    t.type = TokenType.less_equal;
                    t.end = self.pos + 2;
                    self.advance();
                } else {
                    t.type = TokenType.less;
                    return t;
                }
            },
            '>' => {
                if (self.peek() == '=') {
                    t.type = TokenType.greater_equal;
                    t.end = self.pos + 2;
                    self.advance();
                } else {
                    t.type = TokenType.greater;
                    return t;
                }
            },
            '!' => {
                if (self.peek() == '=') {
                    t.type = TokenType.bang_equal;
                    t.end = self.pos + 2;
                    self.advance();
                } else {
                    t.type = TokenType.bang;
                    return t;
                }
            },
            '.' => {
                if (self.peek() == '.') {
                    t.type = TokenType.range;
                    t.end = self.pos + 2;
                    self.advance();
                } else {
                    t.type = TokenType.dot;
                    return t;
                }
            },
            else => {},
        }
        return t;
    }

    fn isIdenStart(self: *Lexer) bool {
        const ch = self.current();
        return std.ascii.isAlphabetic(ch) or ch == '_';
    }

    fn isIdenContinue(self: *Lexer) bool {
        const ch = self.current();
        return std.ascii.isAlphanumeric(ch) or ch == '_';
    }

    fn readIdentifierToken(self: *Lexer) Token {
        var t = Token{ .type = TokenType.identifier, .start = self.pos, .end = self.pos };
        while (self.isIdenContinue()) {
            self.advance();
        }
        t.end = self.pos;
        if (keywords.get(self.input[t.start..t.end])) |kw| {
            t.type = kw;
        }
        return t;
    }

    fn isDigit(self: *Lexer) bool {
        const ch = self.current();
        return std.ascii.isDigit(ch);
    }

    fn readNumberToken(self: *Lexer) Token {
        var t = Token{ .type = TokenType.integer, .start = self.pos, .end = self.pos };
        while (self.isDigit()) {
            self.advance();
        }
        t.end = self.pos;
        return t;
    }

    fn isCommentStart(self: *Lexer) bool {
        return self.peek() == '/' and self.current() == '/';
    }

    fn isCommentEnd(self: *Lexer) bool {
        if (self.pos + 1 >= self.input.len) {
            return true;
        }
        const ch = self.current();
        return ch == '\n' or ch == '\r';
    }

    fn eatComment(self: *Lexer) void {
        while (!self.isCommentEnd()) {
            self.advance();
        }
        self.advance();
    }

    fn eatWhitespace(self: *Lexer) void {
        while (std.ascii.isWhitespace(self.current())) {
            self.advance();
        }
    }

    fn eatTrivia(self: *Lexer) void {
        while (true) {
            self.eatWhitespace();
            if (!self.isCommentStart()) {
                return;
            }
            self.eatComment();
        }
    }

    // This assumes that the token is from the same source created by this lexer.
    // Currently we don't have a way to enforce this.
    pub fn lexeme(self: *Lexer, t: Token) []const u8 {
        std.debug.assert(t.start <= t.end);
        std.debug.assert(t.end <= self.input.len);
        return self.input[t.start..t.end];
    }

    pub fn next(self: *Lexer) Token {
        self.eatTrivia();
        if (self.isAtEnd()) {
            return Token{
                .type = TokenType.eof,
                .start = self.pos,
                .end = self.pos,
            };
        }
        var t = Token{
            .type = TokenType.illegal,
            .start = self.pos,
            .end = self.pos + 1,
        };
        switch (self.current()) {
            '&', '|', '-', '?', ':', ',', '*', '#', '{', '}', '[', ']', '(', ')' => {
                t = self.readSingleCharToken();
            },
            '=', '<', '>', '!', '.' => {
                t = self.readLookaheadCharToken();
            },
            else => {
                if (self.isIdenStart()) {
                    t = self.readIdentifierToken();
                    return t;
                }
                if (self.isDigit()) {
                    t = self.readNumberToken();
                    return t;
                }
            },
        }
        self.advance();
        return t;
    }
};

const ExpectedToken = struct {
    type: TokenType,
    lexeme: []const u8,
};

fn expectTokens(input: []const u8, expected: []const ExpectedToken) !void {
    try testing.expect(expected.len > 0);
    try testing.expectEqual(TokenType.eof, expected[expected.len - 1].type);

    var lexer = Lexer.init(input);
    for (expected) |want| {
        const actual = lexer.next();
        try testing.expectEqual(want.type, actual.type);
        try testing.expectEqualStrings(want.lexeme, lexer.lexeme(actual));
        if (actual.type == .eof) {
            try testing.expectEqual(input.len, actual.start);
            try testing.expectEqual(input.len, actual.end);
        }
    }
}

test "single character tokens" {
    const input = "&|-?:,*#{}[]()";
    const expected = [_]ExpectedToken{
        .{ .type = .ampersand, .lexeme = "&" }, .{ .type = .pipe, .lexeme = "|" },
        .{ .type = .minus, .lexeme = "-" },     .{ .type = .question, .lexeme = "?" },
        .{ .type = .colon, .lexeme = ":" },     .{ .type = .comma, .lexeme = "," },
        .{ .type = .star, .lexeme = "*" },      .{ .type = .hash, .lexeme = "#" },
        .{ .type = .l_brace, .lexeme = "{" },   .{ .type = .r_brace, .lexeme = "}" },
        .{ .type = .l_bracket, .lexeme = "[" }, .{ .type = .r_bracket, .lexeme = "]" },
        .{ .type = .l_paren, .lexeme = "(" },   .{ .type = .r_paren, .lexeme = ")" },
        .{ .type = .eof, .lexeme = "" },
    };
    try expectTokens(input, &expected);
}

test "lookahead tokens" {
    const input = "= < > == <= >= != .. .!";
    const expected = [_]ExpectedToken{
        .{ .type = .assign, .lexeme = "=" },      .{ .type = .less, .lexeme = "<" },
        .{ .type = .greater, .lexeme = ">" },     .{ .type = .equal_equal, .lexeme = "==" },
        .{ .type = .less_equal, .lexeme = "<=" }, .{ .type = .greater_equal, .lexeme = ">=" },
        .{ .type = .bang_equal, .lexeme = "!=" }, .{ .type = .range, .lexeme = ".." },
        .{ .type = .dot, .lexeme = "." },         .{ .type = .bang, .lexeme = "!" },
        .{ .type = .eof, .lexeme = "" },
    };
    try expectTokens(input, &expected);
}

test "lookahead tokens same first char consecutive" {
    const input = "= == . .. == = .. .";
    const expected = [_]ExpectedToken{
        .{ .type = .assign, .lexeme = "=" },       .{ .type = .equal_equal, .lexeme = "==" },
        .{ .type = .dot, .lexeme = "." },          .{ .type = .range, .lexeme = ".." },
        .{ .type = .equal_equal, .lexeme = "==" }, .{ .type = .assign, .lexeme = "=" },
        .{ .type = .range, .lexeme = ".." },       .{ .type = .dot, .lexeme = "." },
        .{ .type = .eof, .lexeme = "" },
    };
    try expectTokens(input, &expected);
}

test "keywords" {
    const input = "type relation permission condition with in self";
    const expected = [_]ExpectedToken{
        .{ .type = .kw_type, .lexeme = "type" },             .{ .type = .kw_relation, .lexeme = "relation" },
        .{ .type = .kw_permission, .lexeme = "permission" }, .{ .type = .kw_condition, .lexeme = "condition" },
        .{ .type = .kw_with, .lexeme = "with" },             .{ .type = .kw_in, .lexeme = "in" },
        .{ .type = .kw_self, .lexeme = "self" },             .{ .type = .eof, .lexeme = "" },
    };
    try expectTokens(input, &expected);
}

test "identifiers" {
    const input = "foo bar baz foo_bar foo1";
    const expected = [_]ExpectedToken{
        .{ .type = .identifier, .lexeme = "foo" },  .{ .type = .identifier, .lexeme = "bar" },
        .{ .type = .identifier, .lexeme = "baz" },  .{ .type = .identifier, .lexeme = "foo_bar" },
        .{ .type = .identifier, .lexeme = "foo1" }, .{ .type = .eof, .lexeme = "" },
    };
    try expectTokens(input, &expected);
}

test "integers" {
    const input = "0 1 1234567890";
    const expected = [_]ExpectedToken{
        .{ .type = .integer, .lexeme = "0" },          .{ .type = .integer, .lexeme = "1" },
        .{ .type = .integer, .lexeme = "1234567890" }, .{ .type = .eof, .lexeme = "" },
    };
    try expectTokens(input, &expected);
}

test "comments" {
    const input = "// this is a comment\n// this is another comment\r// this is yet another comment\r\n";
    const expected = [_]ExpectedToken{.{ .type = .eof, .lexeme = "" }};
    try expectTokens(input, &expected);
}

test "illegal characters" {
    const input = "\\ / @ $ %";
    const expected = [_]ExpectedToken{
        .{ .type = .illegal, .lexeme = "\\" }, .{ .type = .illegal, .lexeme = "/" },
        .{ .type = .illegal, .lexeme = "@" },  .{ .type = .illegal, .lexeme = "$" },
        .{ .type = .illegal, .lexeme = "%" },  .{ .type = .eof, .lexeme = "" },
    };
    try expectTokens(input, &expected);
}

test "embedded null" {
    const input = "\x00User\x00Service\x00";
    const expected = [_]ExpectedToken{
        .{ .type = .illegal, .lexeme = "\x00" },
        .{ .type = .identifier, .lexeme = "User" },
        .{ .type = .illegal, .lexeme = "\x00" },
        .{ .type = .identifier, .lexeme = "Service" },
        .{ .type = .illegal, .lexeme = "\x00" },
        .{ .type = .eof, .lexeme = "" },
    };
    try expectTokens(input, &expected);
}

test "simple type with cardinality bounds and comments" {
    const input =
        \\//this is a comment
        \\//this is another comment
        \\//
        \\type Team {
        \\//this is a comment
        \\    relation member[0..10]: User
        \\    permission members = member
        \\}
        \\//comment at the EOF
        \\//another comment
        \\//
    ;
    const expected = [_]ExpectedToken{
        .{ .type = .kw_type, .lexeme = "type" },             .{ .type = .identifier, .lexeme = "Team" },
        .{ .type = .l_brace, .lexeme = "{" },                .{ .type = .kw_relation, .lexeme = "relation" },
        .{ .type = .identifier, .lexeme = "member" },        .{ .type = .l_bracket, .lexeme = "[" },
        .{ .type = .integer, .lexeme = "0" },                .{ .type = .range, .lexeme = ".." },
        .{ .type = .integer, .lexeme = "10" },               .{ .type = .r_bracket, .lexeme = "]" },
        .{ .type = .colon, .lexeme = ":" },                  .{ .type = .identifier, .lexeme = "User" },
        .{ .type = .kw_permission, .lexeme = "permission" }, .{ .type = .identifier, .lexeme = "members" },
        .{ .type = .assign, .lexeme = "=" },                 .{ .type = .identifier, .lexeme = "member" },
        .{ .type = .r_brace, .lexeme = "}" },                .{ .type = .eof, .lexeme = "" },
    };
    try expectTokens(input, &expected);
}

test "full model" {
    const input =
        \\type User {}
        \\
        \\type Team {
        \\  relation member[0..10]: User with expiration?
        \\}
        \\
        \\condition allowed_ip(source_ip: IpAddress, networks: Network[]) {
        \\  networks.any(network, network.contains(source_ip))
        \\}
        \\
        \\type Project {
        \\  relation organisation[1..1]: Organisation
        \\  relation reader:
        \\    User with u in organisation.members |
        \\    Team#member with t in organisation.team
        \\
        \\  permission read = (reader | organisation.admins) - blocked
        \\}
    ;

    const expected = [_]ExpectedToken{
        .{ .type = .kw_type, .lexeme = "type" },
        .{ .type = .identifier, .lexeme = "User" },
        .{ .type = .l_brace, .lexeme = "{" },
        .{ .type = .r_brace, .lexeme = "}" },

        .{ .type = .kw_type, .lexeme = "type" },
        .{ .type = .identifier, .lexeme = "Team" },
        .{ .type = .l_brace, .lexeme = "{" },
        .{ .type = .kw_relation, .lexeme = "relation" },
        .{ .type = .identifier, .lexeme = "member" },
        .{ .type = .l_bracket, .lexeme = "[" },
        .{ .type = .integer, .lexeme = "0" },
        .{ .type = .range, .lexeme = ".." },
        .{ .type = .integer, .lexeme = "10" },
        .{ .type = .r_bracket, .lexeme = "]" },
        .{ .type = .colon, .lexeme = ":" },
        .{ .type = .identifier, .lexeme = "User" },
        .{ .type = .kw_with, .lexeme = "with" },
        .{ .type = .identifier, .lexeme = "expiration" },
        .{ .type = .question, .lexeme = "?" },
        .{ .type = .r_brace, .lexeme = "}" },

        .{ .type = .kw_condition, .lexeme = "condition" },
        .{ .type = .identifier, .lexeme = "allowed_ip" },
        .{ .type = .l_paren, .lexeme = "(" },
        .{ .type = .identifier, .lexeme = "source_ip" },
        .{ .type = .colon, .lexeme = ":" },
        .{ .type = .identifier, .lexeme = "IpAddress" },
        .{ .type = .comma, .lexeme = "," },
        .{ .type = .identifier, .lexeme = "networks" },
        .{ .type = .colon, .lexeme = ":" },
        .{ .type = .identifier, .lexeme = "Network" },
        .{ .type = .l_bracket, .lexeme = "[" },
        .{ .type = .r_bracket, .lexeme = "]" },
        .{ .type = .r_paren, .lexeme = ")" },
        .{ .type = .l_brace, .lexeme = "{" },
        .{ .type = .identifier, .lexeme = "networks" },
        .{ .type = .dot, .lexeme = "." },
        .{ .type = .identifier, .lexeme = "any" },
        .{ .type = .l_paren, .lexeme = "(" },
        .{ .type = .identifier, .lexeme = "network" },
        .{ .type = .comma, .lexeme = "," },
        .{ .type = .identifier, .lexeme = "network" },
        .{ .type = .dot, .lexeme = "." },
        .{ .type = .identifier, .lexeme = "contains" },
        .{ .type = .l_paren, .lexeme = "(" },
        .{ .type = .identifier, .lexeme = "source_ip" },
        .{ .type = .r_paren, .lexeme = ")" },
        .{ .type = .r_paren, .lexeme = ")" },
        .{ .type = .r_brace, .lexeme = "}" },

        .{ .type = .kw_type, .lexeme = "type" },
        .{ .type = .identifier, .lexeme = "Project" },
        .{ .type = .l_brace, .lexeme = "{" },
        .{ .type = .kw_relation, .lexeme = "relation" },
        .{ .type = .identifier, .lexeme = "organisation" },
        .{ .type = .l_bracket, .lexeme = "[" },
        .{ .type = .integer, .lexeme = "1" },
        .{ .type = .range, .lexeme = ".." },
        .{ .type = .integer, .lexeme = "1" },
        .{ .type = .r_bracket, .lexeme = "]" },
        .{ .type = .colon, .lexeme = ":" },
        .{ .type = .identifier, .lexeme = "Organisation" },
        .{ .type = .kw_relation, .lexeme = "relation" },
        .{ .type = .identifier, .lexeme = "reader" },
        .{ .type = .colon, .lexeme = ":" },
        .{ .type = .identifier, .lexeme = "User" },
        .{ .type = .kw_with, .lexeme = "with" },
        .{ .type = .identifier, .lexeme = "u" },
        .{ .type = .kw_in, .lexeme = "in" },
        .{ .type = .identifier, .lexeme = "organisation" },
        .{ .type = .dot, .lexeme = "." },
        .{ .type = .identifier, .lexeme = "members" },
        .{ .type = .pipe, .lexeme = "|" },
        .{ .type = .identifier, .lexeme = "Team" },
        .{ .type = .hash, .lexeme = "#" },
        .{ .type = .identifier, .lexeme = "member" },
        .{ .type = .kw_with, .lexeme = "with" },
        .{ .type = .identifier, .lexeme = "t" },
        .{ .type = .kw_in, .lexeme = "in" },
        .{ .type = .identifier, .lexeme = "organisation" },
        .{ .type = .dot, .lexeme = "." },
        .{ .type = .identifier, .lexeme = "team" },
        .{ .type = .kw_permission, .lexeme = "permission" },
        .{ .type = .identifier, .lexeme = "read" },
        .{ .type = .assign, .lexeme = "=" },
        .{ .type = .l_paren, .lexeme = "(" },
        .{ .type = .identifier, .lexeme = "reader" },
        .{ .type = .pipe, .lexeme = "|" },
        .{ .type = .identifier, .lexeme = "organisation" },
        .{ .type = .dot, .lexeme = "." },
        .{ .type = .identifier, .lexeme = "admins" },
        .{ .type = .r_paren, .lexeme = ")" },
        .{ .type = .minus, .lexeme = "-" },
        .{ .type = .identifier, .lexeme = "blocked" },
        .{ .type = .r_brace, .lexeme = "}" },
        .{ .type = .eof, .lexeme = "" },
    };

    try expectTokens(input, &expected);
}
