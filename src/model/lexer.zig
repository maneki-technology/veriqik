const token_module = @import("token.zig");
const Token = token_module.Token;
const TokenType = token_module.TokenType;
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
    position: usize,

    pub fn init(input: []const u8) Lexer {
        const lexer = Lexer{
            .input = input,
            .position = 0,
        };

        return lexer;
    }

    fn is_at_end(self: *Lexer) bool {
        return self.position >= self.input.len;
    }

    fn current(self: *Lexer) u8 {
        if (self.is_at_end()) {
            return 0;
        }
        return self.input[self.position];
    }

    fn advance(self: *Lexer) void {
        if (self.is_at_end()) {
            return;
        }
        self.position += 1;
    }

    fn read_single_character_token(self: *Lexer) Token {
        var token = Token{
            .type = TokenType.illegal,
            .start = self.position,
            .end = self.position + 1,
        };
        switch (self.current()) {
            '&' => {
                token.type = TokenType.ampersand;
            },
            '|' => {
                token.type = TokenType.pipe;
            },
            '-' => {
                token.type = TokenType.minus;
            },
            '?' => {
                token.type = TokenType.question;
            },
            ':' => {
                token.type = TokenType.colon;
            },
            ',' => {
                token.type = TokenType.comma;
            },
            '*' => {
                token.type = TokenType.star;
            },
            '#' => {
                token.type = TokenType.hash;
            },
            '{' => {
                token.type = TokenType.l_brace;
            },
            '}' => {
                token.type = TokenType.r_brace;
            },
            '[' => {
                token.type = TokenType.l_bracket;
            },
            ']' => {
                token.type = TokenType.r_bracket;
            },
            '(' => {
                token.type = TokenType.l_paren;
            },
            ')' => {
                token.type = TokenType.r_paren;
            },
            else => {},
        }
        return token;
    }

    fn peek(self: *Lexer) u8 {
        if (self.position + 1 >= self.input.len) {
            return 0;
        }
        return self.input[self.position + 1];
    }

    fn read_lookahead_character_token(self: *Lexer) Token {
        var token = Token{
            .type = TokenType.illegal,
            .start = self.position,
            .end = self.position + 1,
        };
        switch (self.current()) {
            '=' => {
                if (self.peek() == '=') {
                    token.type = TokenType.equal_equal;
                    token.end = self.position + 2;
                    self.advance();
                } else {
                    token.type = TokenType.assign;
                    return token;
                }
            },
            '<' => {
                if (self.peek() == '=') {
                    token.type = TokenType.less_equal;
                    token.end = self.position + 2;
                    self.advance();
                } else {
                    token.type = TokenType.less;
                    return token;
                }
            },
            '>' => {
                if (self.peek() == '=') {
                    token.type = TokenType.greater_equal;
                    token.end = self.position + 2;
                    self.advance();
                } else {
                    token.type = TokenType.greater;
                    return token;
                }
            },
            '!' => {
                if (self.peek() == '=') {
                    token.type = TokenType.bang_equal;
                    token.end = self.position + 2;
                    self.advance();
                } else {
                    token.type = TokenType.bang;
                    return token;
                }
            },
            '.' => {
                if (self.peek() == '.') {
                    token.type = TokenType.range;
                    token.end = self.position + 2;
                    self.advance();
                } else {
                    token.type = TokenType.dot;
                    return token;
                }
            },
            else => {},
        }
        return token;
    }

    fn is_identifier_start(self: *Lexer) bool {
        return std.ascii.isAlphabetic(self.current()) or self.current() == '_';
    }

    fn is_identifier_continue(self: *Lexer) bool {
        return std.ascii.isAlphanumeric(self.current()) or self.current() == '_';
    }

    fn read_identifier_token(self: *Lexer) Token {
        var token = Token{ .type = TokenType.identifier, .start = self.position, .end = self.position };
        while (self.is_identifier_continue()) {
            self.advance();
        }
        token.end = self.position;
        if (keywords.get(self.input[token.start..token.end])) |keyword| {
            token.type = keyword;
        }
        return token;
    }

    fn is_digit(self: *Lexer) bool {
        return std.ascii.isDigit(self.current());
    }

    fn read_number_token(self: *Lexer) Token {
        var token = Token{ .type = TokenType.integer, .start = self.position, .end = self.position };
        while (self.is_digit()) {
            self.advance();
        }
        token.end = self.position;
        return token;
    }

    fn is_comment_start(self: *Lexer) bool {
        return self.peek() == '/' and self.current() == '/';
    }

    fn is_comment_end(self: *Lexer) bool {
        if (self.position + 1 >= self.input.len) {
            return true;
        }
        return self.current() == '\n' or self.current() == '\r';
    }

    fn eat_comment(self: *Lexer) void {
        while (!self.is_comment_end()) {
            self.advance();
        }
        self.advance();
    }

    fn eat_whitespace(self: *Lexer) void {
        while (std.ascii.isWhitespace(self.current())) {
            self.advance();
        }
    }

    fn eat_trivia(self: *Lexer) void {
        while (true) {
            self.eat_whitespace();
            if (!self.is_comment_start()) {
                return;
            }
            self.eat_comment();
        }
    }

    // This assumes that the token is from the same source created by this lexer.
    // Currently we don't have a way to enforce this.
    pub fn lexeme(self: *Lexer, token: Token) []const u8 {
        std.debug.assert(token.start <= token.end);
        std.debug.assert(token.end <= self.input.len);
        return self.input[token.start..token.end];
    }

    pub fn next(self: *Lexer) Token {
        self.eat_trivia();
        if (self.is_at_end()) {
            return Token{
                .type = TokenType.eof,
                .start = self.position,
                .end = self.position,
            };
        }
        var token = Token{
            .type = TokenType.illegal,
            .start = self.position,
            .end = self.position + 1,
        };
        switch (self.current()) {
            '&', '|', '-', '?', ':', ',', '*', '#', '{', '}', '[', ']', '(', ')' => {
                token = self.read_single_character_token();
            },
            '=', '<', '>', '!', '.' => {
                token = self.read_lookahead_character_token();
            },
            else => {
                if (self.is_identifier_start()) {
                    token = self.read_identifier_token();
                    return token;
                }
                if (self.is_digit()) {
                    token = self.read_number_token();
                    return token;
                }
            },
        }
        self.advance();
        return token;
    }
};

const ExpectedToken = struct {
    type: TokenType,
    lexeme: []const u8,
};

fn expect_tokens(input: []const u8, expected: []const ExpectedToken) !void {
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
    try expect_tokens(input, &expected);
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
    try expect_tokens(input, &expected);
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
    try expect_tokens(input, &expected);
}

test "keywords" {
    const input = "type relation permission condition with in self";
    const expected = [_]ExpectedToken{
        .{ .type = .kw_type, .lexeme = "type" },             .{ .type = .kw_relation, .lexeme = "relation" },
        .{ .type = .kw_permission, .lexeme = "permission" }, .{ .type = .kw_condition, .lexeme = "condition" },
        .{ .type = .kw_with, .lexeme = "with" },             .{ .type = .kw_in, .lexeme = "in" },
        .{ .type = .kw_self, .lexeme = "self" },             .{ .type = .eof, .lexeme = "" },
    };
    try expect_tokens(input, &expected);
}

test "identifiers" {
    const input = "foo bar baz foo_bar foo1";
    const expected = [_]ExpectedToken{
        .{ .type = .identifier, .lexeme = "foo" },  .{ .type = .identifier, .lexeme = "bar" },
        .{ .type = .identifier, .lexeme = "baz" },  .{ .type = .identifier, .lexeme = "foo_bar" },
        .{ .type = .identifier, .lexeme = "foo1" }, .{ .type = .eof, .lexeme = "" },
    };
    try expect_tokens(input, &expected);
}

test "integers" {
    const input = "0 1 1234567890";
    const expected = [_]ExpectedToken{
        .{ .type = .integer, .lexeme = "0" },          .{ .type = .integer, .lexeme = "1" },
        .{ .type = .integer, .lexeme = "1234567890" }, .{ .type = .eof, .lexeme = "" },
    };
    try expect_tokens(input, &expected);
}

test "comments" {
    const input = "// this is a comment\n// this is another comment\r// this is yet another comment\r\n";
    const expected = [_]ExpectedToken{.{ .type = .eof, .lexeme = "" }};
    try expect_tokens(input, &expected);
}

test "illegal characters" {
    const input = "\\ / @ $ %";
    const expected = [_]ExpectedToken{
        .{ .type = .illegal, .lexeme = "\\" }, .{ .type = .illegal, .lexeme = "/" },
        .{ .type = .illegal, .lexeme = "@" },  .{ .type = .illegal, .lexeme = "$" },
        .{ .type = .illegal, .lexeme = "%" },  .{ .type = .eof, .lexeme = "" },
    };
    try expect_tokens(input, &expected);
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
    try expect_tokens(input, &expected);
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
    try expect_tokens(input, &expected);
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

    try expect_tokens(input, &expected);
}
