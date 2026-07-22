const std = @import("std");
const ArrayList = std.ArrayList([]u8);
const Map = std.StringHashMapUnmanaged(SymbolId);
const testing = std.testing;

pub const SymbolId = enum(u16) {
    _,

    pub fn from_int(value: u16) SymbolId {
        return @enumFromInt(value);
    }

    pub fn to_int(self: SymbolId) u16 {
        return @intFromEnum(self);
    }
};

const InternerError = error{
    TooManySymbols,
};

pub const Interner = struct {
    allocator: std.mem.Allocator,
    name_by_id: ArrayList,
    id_by_name: Map,
    limit: usize,

    pub fn init(allocator: std.mem.Allocator, limit: usize) Interner {
        return .{
            .allocator = allocator,
            .name_by_id = .empty,
            .id_by_name = .empty,
            .limit = limit,
        };
    }

    pub fn deinit(self: *Interner) void {
        for (self.name_by_id.items) |name| {
            self.allocator.free(name);
        }
        self.name_by_id.deinit(self.allocator);
        self.id_by_name.deinit(self.allocator);
    }

    pub fn intern(self: *Interner, name: []const u8) !SymbolId {
        const interned = self.id_by_name.get(name) orelse {
            const id = self.name_by_id.items.len;
            if (id > self.limit) {
                return InternerError.TooManySymbols;
            }

            const duped_name = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(duped_name);

            try self.name_by_id.append(self.allocator, duped_name);
            errdefer _ = self.name_by_id.pop();

            const symbolId = SymbolId.from_int(@as(u16, @intCast(id)));
            try self.id_by_name.put(self.allocator, duped_name, symbolId);

            return symbolId;
        };
        return interned;
    }
};

test "interner" {
    var interner = Interner.init(std.testing.allocator, std.math.maxInt(u16));
    defer interner.deinit();

    try testing.expectEqual(SymbolId.from_int(0), try interner.intern("foo"));
    try testing.expectEqual(SymbolId.from_int(1), try interner.intern("bar"));
    try testing.expectEqual(SymbolId.from_int(0), try interner.intern("foo"));
    try testing.expectEqual(SymbolId.from_int(1), try interner.intern("bar"));
}

test "interner max symbols" {
    const allocator = std.testing.allocator;
    const limit = 8;
    var interner = Interner.init(allocator, limit);
    defer interner.deinit();

    var i: usize = 0;
    while (i <= limit) : (i += 1) {
        const symbol = try std.fmt.allocPrint(allocator, "foo{}", .{i});
        defer allocator.free(symbol);
        _ = try interner.intern(symbol);
    }
    try testing.expectError(InternerError.TooManySymbols, interner.intern("foo"));
}
