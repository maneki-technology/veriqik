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

pub const Cardinality = struct {
    min: usize = 0,
    max: ?usize,
};

pub const Relation = struct {
    name: Identifier,
    cardinality: ?Cardinality,
    // TODO: relation expression
    span: Span,
};

pub const Permission = struct {};

pub const Type = struct {
    name: Identifier,
    relations: []const Relation = &.{},
    span: Span,

    pub fn deinit(self: *const Type, allocator: std.mem.Allocator) void {
        allocator.free(self.relations);
    }
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
    parameters: []const Parameter = &.{},
    span: Span,

    pub fn deinit(self: *const Condition, allocator: std.mem.Allocator) void {
        allocator.free(self.parameters);
    }
};

pub const Model = struct {
    types: []const Type = &.{},
    conditions: []const Condition = &.{},

    pub fn deinit(self: *Model, allocator: std.mem.Allocator) void {
        for (self.types) |*type_decl| {
            type_decl.deinit(allocator);
        }
        allocator.free(self.types);
        for (self.conditions) |*condition| {
            condition.deinit(allocator);
        }
        allocator.free(self.conditions);
        self.* = undefined;
    }
};
