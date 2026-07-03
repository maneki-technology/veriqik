pub const TokenType = enum(u8) {
    illegal,
    eof,

    // Keywords
    kw_type,
    kw_relation,
    kw_permission,
    kw_condition,
    kw_with,
    kw_in,
    kw_self,

    // Names and literals
    identifier,
    integer,

    // Punctuation
    assign, // =
    colon,
    comma,
    hash, // #

    // Set and boolean operators
    pipe, // |
    ampersand, // &
    minus, // -
    bang, // !
    dot, // .

    // Comparisons
    equal_equal, // ==
    bang_equal, // !=
    less, // <
    less_equal, // <=
    greater, // >
    greater_equal, // >=

    // Cardinality and collection types
    l_bracket,
    r_bracket,
    range, // ..
    star, // *

    question, // ?

    // Grouping
    l_brace,
    r_brace,
    l_paren,
    r_paren,
};

pub const Token = struct {
    start: usize,
    end: usize,
    type: TokenType,
};
