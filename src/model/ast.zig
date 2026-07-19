const std = @import("std");
const SymbolId = @import("symbol.zig").SymbolId;

pub const Span = struct {
    start: usize,
    end: usize,
};

pub const Identifier = struct {
    symbol: SymbolId,
    span: Span,
};

pub const Relation = struct {};

pub const Permission = struct {};

pub const Type = struct {
    name: Identifier,
    span: Span,
};

pub const Condition = struct {};

pub const Model = struct {
    types: []const Type = &.{},

    pub fn deinit(self: *Model, allocator: std.mem.Allocator) void {
        allocator.free(self.types);
        self.* = undefined;
    }
};
