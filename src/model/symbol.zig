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
    IdentifierTooLong,
};

pub const Interner = struct {
    allocator: std.mem.Allocator,
    name_by_id: ArrayList,
    id_by_name: Map,
    symbol_count_max: usize,
    identifier_bytes_max: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        symbol_count_max: usize,
        identifier_bytes_max: usize,
    ) Interner {
        return .{
            .allocator = allocator,
            .name_by_id = .empty,
            .id_by_name = .empty,
            .symbol_count_max = symbol_count_max,
            .identifier_bytes_max = identifier_bytes_max,
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
            if (id >= self.symbol_count_max) {
                return InternerError.TooManySymbols;
            }

            if (name.len > self.identifier_bytes_max) {
                return InternerError.IdentifierTooLong;
            }

            const name_owned = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(name_owned);

            try self.name_by_id.append(self.allocator, name_owned);
            errdefer _ = self.name_by_id.pop();

            const symbol_id = SymbolId.from_int(@as(u16, @intCast(id)));
            try self.id_by_name.put(self.allocator, name_owned, symbol_id);

            return symbol_id;
        };
        return interned;
    }
};

test "interner" {
    var interner = Interner.init(std.testing.allocator, std.math.maxInt(u16), 255);
    defer interner.deinit();

    try testing.expectEqual(SymbolId.from_int(0), try interner.intern("foo"));
    try testing.expectEqual(SymbolId.from_int(1), try interner.intern("bar"));
    try testing.expectEqual(SymbolId.from_int(0), try interner.intern("foo"));
    try testing.expectEqual(SymbolId.from_int(1), try interner.intern("bar"));
}

test "interner max symbols" {
    const allocator = std.testing.allocator;
    const symbol_count_max = 8;
    const identifier_bytes_max = 255;
    var interner = Interner.init(allocator, symbol_count_max, identifier_bytes_max);
    defer interner.deinit();

    var i: usize = 0;
    while (i < symbol_count_max) : (i += 1) {
        const symbol = try std.fmt.allocPrint(allocator, "foo{}", .{i});
        defer allocator.free(symbol);
        _ = try interner.intern(symbol);
    }
    try testing.expectError(InternerError.TooManySymbols, interner.intern("foo"));
}
