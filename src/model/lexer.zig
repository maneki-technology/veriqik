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
    readPos: usize,

    pub fn init(input: []const u8) Lexer {
        var lexer = Lexer{
            .input = input,
            .pos = 0,
            .readPos = 0,
        };

        lexer.readChar();
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

    fn readChar(self: *Lexer) void {
        self.pos = self.readPos;
        if (self.isAtEnd()) {
            return;
        }
        self.readPos += 1;
    }

    fn readSingleCharToken(self: *Lexer) Token {
        var t = Token{
            .type = TokenType.illegal,
            .start = self.pos,
            .end = self.readPos,
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
        if (self.readPos >= self.input.len) {
            return 0;
        }
        return self.input[self.readPos];
    }

    fn readLookaheadCharToken(self: *Lexer) Token {
        var t = Token{
            .type = TokenType.illegal,
            .start = self.pos,
            .end = self.readPos,
        };
        const nextCh = self.peek();
        switch (self.current()) {
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

    fn isIdenStart(self: *Lexer) bool {
        return std.ascii.isAlphabetic(self.current()) or self.current() == '_';
    }

    fn isIdenContinue(self: *Lexer) bool {
        return std.ascii.isAlphanumeric(self.current()) or self.current() == '_';
    }

    fn readIdentifierToken(self: *Lexer) Token {
        var t = Token{ .type = TokenType.identifier, .start = self.pos, .end = self.pos };
        while (self.isIdenContinue()) {
            self.readChar();
        }
        t.end = self.pos;
        if (keywords.get(self.input[t.start..t.end])) |kw| {
            t.type = kw;
        }
        return t;
    }

    fn isDigit(self: *Lexer) bool {
        return std.ascii.isDigit(self.current());
    }

    fn readNumberToken(self: *Lexer) Token {
        var t = Token{ .type = TokenType.integer, .start = self.pos, .end = self.pos };
        while (self.isDigit()) {
            self.readChar();
        }
        t.end = self.pos;
        return t;
    }

    fn isCommentStart(self: *Lexer) bool {
        const nextCh = self.peek();
        return nextCh == '/' and self.current() == '/';
    }

    fn isCommentEnd(self: *Lexer) bool {
        if (self.readPos >= self.input.len) {
            return true;
        }
        return self.current() == '\n' or self.current() == '\r';
    }

    fn eatComment(self: *Lexer) void {
        while (!self.isCommentEnd()) {
            self.readChar();
        }
        self.readChar();
    }

    fn eatWhitespace(self: *Lexer) void {
        while (std.ascii.isWhitespace(self.current())) {
            self.readChar();
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
            .end = self.readPos,
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
        self.readChar();
        return t;
    }
};

const ExpectedToken = struct {
    type: TokenType,
    lexeme: []const u8,
};

fn expectTokens(input: []const u8, expected: []const ExpectedToken) !void {
    var lexer = Lexer.init(input);
    for (expected) |want| {
        const actual = lexer.next();
        try testing.expectEqual(want.type, actual.type);
        try testing.expectEqualStrings(want.lexeme, input[actual.start..actual.end]);
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
