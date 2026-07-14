//! By convention, root.zig is the root source file when making a package.
//! import all the other source files in your package from here for zig to run all tests in your package.
const std = @import("std");
pub const lexer = @import("lexer.zig");

test {
    std.testing.refAllDecls(@This());
}
