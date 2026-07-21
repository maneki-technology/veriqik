pub const model = struct {
    pub const ast = @import("model/ast.zig");
    pub const lexer = @import("model/lexer.zig");
    pub const parser = @import("model/parser.zig");
    pub const symbol = @import("model/symbol.zig");
    pub const token = @import("model/token.zig");
};

test {
    _ = model.ast;
    _ = model.lexer;
    _ = model.parser;
    _ = model.symbol;
    _ = model.token;
}
