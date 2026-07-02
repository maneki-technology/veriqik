pub const TokenType = enum {
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
    kw_resource,

    // Names and literals
    identifier,
    integer_literal,
    string_literal,
    kw_true,
    kw_false,

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
    type: TokenType,
    start: usize,
    end: usize,
};
