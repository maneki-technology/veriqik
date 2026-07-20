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

pub const ValueTypeRef = struct {
    name: Identifier,
    span: Span,
    collection: bool,
};

pub const Parameter = struct {
    name: Identifier,
    type: ValueTypeRef,
    span: Span,
};

pub const Condition = struct {
    name: Identifier,
    params: []const Parameter = &.{},
    span: Span,

    pub fn deinit(self: *const Condition, allocator: std.mem.Allocator) void {
        allocator.free(self.params);
    }
};

pub const Model = struct {
    types: []const Type = &.{},
    conditions: []const Condition = &.{},

    pub fn deinit(self: *Model, allocator: std.mem.Allocator) void {
        allocator.free(self.types);
        for (self.conditions) |*cond| {
            cond.deinit(allocator);
        }
        allocator.free(self.conditions);
        self.* = undefined;
    }
};
