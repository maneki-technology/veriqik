const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const demo_schema = @embedFile("fixtures/demo/schema.vq");
const demo_tuples = @embedFile("fixtures/demo/tuples.txt");
const load_schema = @embedFile("fixtures/load/schema.vq");

const tuple_storage_bytes_per_tuple_estimate: usize = 192;
const dictionary_bytes_per_name_estimate: usize = 160;
const check_bytes_per_item_estimate: usize = 160;
const load_fixed_bytes_estimate: usize = 4 * 1024 * 1024;
const load_memory_budget_bytes: usize = 20 * 1024 * 1024 * 1024;
const load_max_depth: u32 = 128;
const load_documents_per_folder: usize = 1000;
const load_max_folders: usize = 100_000;
const load_folder_parent_fanout: usize = 16;
const load_group_chain_depth: usize = 8;

const MeteredAllocator = struct {
    child: Allocator,
    allocated_current_bytes: usize = 0,
    allocated_peak_bytes: usize = 0,
    alloc_count: usize = 0,
    free_count: usize = 0,

    fn init(child: Allocator) MeteredAllocator {
        return .{ .child = child };
    }

    fn allocator(self: *MeteredAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *MeteredAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.alloc_count += 1;
        self.grow(len);
        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *MeteredAllocator = @ptrCast(@alignCast(ctx));
        if (!self.child.rawResize(memory, alignment, new_len, ret_addr)) return false;
        self.recordResize(memory.len, new_len);
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *MeteredAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        self.recordResize(memory.len, new_len);
        return ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *MeteredAllocator = @ptrCast(@alignCast(ctx));
        self.shrink(memory.len);
        self.free_count += 1;
        self.child.rawFree(memory, alignment, ret_addr);
    }

    fn recordResize(self: *MeteredAllocator, old_len: usize, new_len: usize) void {
        if (new_len > old_len) {
            self.grow(new_len - old_len);
        } else {
            self.shrink(old_len - new_len);
        }
    }

    fn grow(self: *MeteredAllocator, amount: usize) void {
        self.allocated_current_bytes += amount;
        self.allocated_peak_bytes = @max(self.allocated_peak_bytes, self.allocated_current_bytes);
    }

    fn shrink(self: *MeteredAllocator, amount: usize) void {
        self.allocated_current_bytes -= amount;
    }
};

const PhaseTiming = struct {
    elapsed_ns: u64,
    cpu_ns: u64,
};

const LoadProgress = struct {
    io: std.Io,
    meter: *const MeteredAllocator,
    total: usize,
    next_report: usize = 0,
    step: usize,
    buffer: [512]u8 = undefined,

    fn init(io: std.Io, meter: *const MeteredAllocator, total: usize) LoadProgress {
        return .{
            .io = io,
            .meter = meter,
            .total = total,
            .step = @max(1, total / 20),
        };
    }

    fn report(self: *LoadProgress, phase: []const u8, current: usize, tuples: usize, force: bool) !void {
        if (!force and current < self.next_report) return;
        self.next_report = current + self.step;

        var stderr_writer = std.Io.File.stderr().writer(self.io, &self.buffer);
        const stderr = &stderr_writer.interface;
        const percent = if (self.total == 0) 100 else (current * 100) / self.total;
        try stderr.print(
            "progress phase={s} current={} total={} percent={} tuples={} allocated_current_bytes={} allocated_peak_bytes={}\n",
            .{
                phase,
                current,
                self.total,
                percent,
                tuples,
                self.meter.allocated_current_bytes,
                self.meter.allocated_peak_bytes,
            },
        );
        try stderr.flush();
    }
};

fn loadProgressTotal(shape: LoadShape) usize {
    return shape.estimatedDictionaryNames() + shape.estimatedTuples();
}

const LatencySummary = struct {
    avg_ns: u64,
    p50_ns: u64,
    p95_ns: u64,
    p99_ns: u64,
    max_ns: u64,
};

pub const Decision = enum {
    allowed,
    denied,
    failed_closed,
};

const Object = struct {
    typ: []const u8,
    id: []const u8,
};

const Subject = struct {
    object: Object,
    relation: ?[]const u8 = null,
};

const Tuple = struct {
    object: Object,
    relation: []const u8,
    subject: Subject,
};

const AllowedSubject = struct {
    typ: []const u8,
    relation: ?[]const u8 = null,
};

const RelationDef = struct {
    name: []const u8,
    allowed: std.ArrayList(AllowedSubject),

    fn deinit(self: *RelationDef, allocator: Allocator) void {
        allocator.free(self.name);
        for (self.allowed.items) |allowed| {
            allocator.free(allowed.typ);
            if (allowed.relation) |rel| allocator.free(rel);
        }
        self.allowed.deinit(allocator);
    }
};

const BinaryExpr = struct {
    left: *Expr,
    right: *Expr,
};

const Expr = union(enum) {
    ref: []const u8,
    traversal: struct {
        relation: []const u8,
        permission: []const u8,
    },
    union_: BinaryExpr,
    intersection: BinaryExpr,
    difference: BinaryExpr,

    fn deinit(self: *Expr, allocator: Allocator) void {
        switch (self.*) {
            .ref => |name| allocator.free(name),
            .traversal => |t| {
                allocator.free(t.relation);
                allocator.free(t.permission);
            },
            .union_, .intersection, .difference => |binary| {
                binary.left.deinit(allocator);
                allocator.destroy(binary.left);
                binary.right.deinit(allocator);
                allocator.destroy(binary.right);
            },
        }
    }
};

const PermissionDef = struct {
    name: []const u8,
    expr: *Expr,

    fn deinit(self: *PermissionDef, allocator: Allocator) void {
        allocator.free(self.name);
        self.expr.deinit(allocator);
        allocator.destroy(self.expr);
    }
};

const TypeDef = struct {
    name: []const u8,
    relations: std.StringHashMap(RelationDef),
    permissions: std.StringHashMap(PermissionDef),

    fn init(allocator: Allocator, name: []const u8) !TypeDef {
        return .{
            .name = try allocator.dupe(u8, name),
            .relations = std.StringHashMap(RelationDef).init(allocator),
            .permissions = std.StringHashMap(PermissionDef).init(allocator),
        };
    }

    fn deinit(self: *TypeDef, allocator: Allocator) void {
        var rel_it = self.relations.iterator();
        while (rel_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.relations.deinit();

        var perm_it = self.permissions.iterator();
        while (perm_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.permissions.deinit();
        allocator.free(self.name);
    }
};

const Schema = struct {
    allocator: Allocator,
    types: std.StringHashMap(TypeDef),
    version: u64 = 0,

    fn init(allocator: Allocator) Schema {
        return .{
            .allocator = allocator,
            .types = std.StringHashMap(TypeDef).init(allocator),
        };
    }

    fn deinit(self: *Schema) void {
        var it = self.types.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.types.deinit();
    }

    fn getType(self: *const Schema, name: []const u8) ?*const TypeDef {
        return self.types.getPtr(name);
    }

    fn getTypeMut(self: *Schema, name: []const u8) ?*TypeDef {
        return self.types.getPtr(name);
    }
};

const Stats = struct {
    nodes_visited: u64 = 0,
    edges_scanned: u64 = 0,
    index_lookups: u64 = 0,
    memo_hits: u64 = 0,
    memo_misses: u64 = 0,
    max_depth: u32 = 0,

    fn add(self: *Stats, other: Stats) void {
        self.nodes_visited += other.nodes_visited;
        self.edges_scanned += other.edges_scanned;
        self.index_lookups += other.index_lookups;
        self.memo_hits += other.memo_hits;
        self.memo_misses += other.memo_misses;
        self.max_depth = @max(self.max_depth, other.max_depth);
    }
};

pub const CheckResult = struct {
    decision: Decision,
    revision: u64,
    proof: ?[]const u8 = null,
    stats: Stats,
};

const CheckItem = struct {
    subject: []const u8,
    object: []const u8,
    permission: []const u8,
};

const Dictionary = struct {
    allocator: Allocator,
    ids: std.StringHashMap(u32),
    names: std.ArrayList([]const u8),

    fn init(allocator: Allocator) Dictionary {
        return .{
            .allocator = allocator,
            .ids = std.StringHashMap(u32).init(allocator),
            .names = .empty,
        };
    }

    fn deinit(self: *Dictionary) void {
        var it = self.ids.iterator();
        while (it.next()) |entry| self.allocator.free(entry.key_ptr.*);
        self.ids.deinit();
        self.names.deinit(self.allocator);
    }

    fn getOrPut(self: *Dictionary, raw_name: []const u8) !u32 {
        if (self.ids.get(raw_name)) |id| return id;
        const id: u32 = @intCast(self.names.items.len + 1);
        const key = try self.allocator.dupe(u8, raw_name);
        errdefer self.allocator.free(key);
        try self.ids.put(key, id);
        try self.names.append(self.allocator, key);
        return id;
    }

    fn putNewOwned(self: *Dictionary, owned_name: []const u8) !u32 {
        if (self.ids.contains(owned_name)) return error.DuplicateDictionaryName;
        const id: u32 = @intCast(self.names.items.len + 1);
        errdefer {
            _ = self.ids.remove(owned_name);
            self.allocator.free(owned_name);
        }
        try self.ids.put(owned_name, id);
        try self.names.append(self.allocator, owned_name);
        return id;
    }

    fn putNewOwnedAssumeCapacity(self: *Dictionary, owned_name: []const u8) u32 {
        const id: u32 = @intCast(self.names.items.len + 1);
        self.ids.putAssumeCapacityNoClobber(owned_name, id);
        self.names.appendAssumeCapacity(owned_name);
        return id;
    }

    fn get(self: *const Dictionary, raw_name: []const u8) ?u32 {
        return self.ids.get(raw_name);
    }

    fn name(self: *const Dictionary, id: u32) []const u8 {
        return self.names.items[id - 1];
    }
};

const ObjectIdDictionaries = struct {
    allocator: Allocator,
    by_type: std.ArrayList(Dictionary),

    fn init(allocator: Allocator) ObjectIdDictionaries {
        return .{
            .allocator = allocator,
            .by_type = .empty,
        };
    }

    fn deinit(self: *ObjectIdDictionaries) void {
        for (self.by_type.items) |*dictionary| dictionary.deinit();
        self.by_type.deinit(self.allocator);
    }

    fn ensureType(self: *ObjectIdDictionaries, type_id: u32) !*Dictionary {
        if (type_id == 0) return error.InvalidTypeId;
        while (self.by_type.items.len < type_id) {
            try self.by_type.append(self.allocator, Dictionary.init(self.allocator));
        }
        return &self.by_type.items[type_id - 1];
    }

    fn getOrPut(self: *ObjectIdDictionaries, type_id: u32, raw_name: []const u8) !u32 {
        const dictionary = try self.ensureType(type_id);
        return dictionary.getOrPut(raw_name);
    }

    fn putNewOwnedAssumeCapacity(self: *ObjectIdDictionaries, type_id: u32, owned_name: []const u8) !u32 {
        const dictionary = try self.ensureType(type_id);
        return dictionary.putNewOwnedAssumeCapacity(owned_name);
    }

    fn get(self: *const ObjectIdDictionaries, type_id: u32, raw_name: []const u8) ?u32 {
        if (type_id == 0 or type_id > self.by_type.items.len) return null;
        return self.by_type.items[type_id - 1].get(raw_name);
    }

    fn name(self: *const ObjectIdDictionaries, type_id: u32, id: u32) []const u8 {
        return self.by_type.items[type_id - 1].name(id);
    }
};

const NumericTuple = struct {
    object_type: u32,
    object_id: u32,
    relation: u32,
    subject_type: u32,
    subject_id: u32,
    subject_relation: u32 = 0,
};

const NumericObject = struct {
    typ: u32,
    id: u32,
};

const NumericSubject = struct {
    object: NumericObject,
    relation: u32 = 0,
};

const ObjectRelationKey = struct {
    object_type: u32,
    object_id: u32,
    relation: u32,
};

const TypeRelationKey = struct {
    object_type: u32,
    relation: u32,
};

const DenseEntry = struct {
    subject_type: u32 = 0,
    subject_id: u32 = 0,
};

const DenseSingleRelation = struct {
    entries: []DenseEntry,
    count: usize,
};

const DenseSingleIndexStats = struct {
    relations: usize,
    entries: usize,
    populated: usize,
    estimated_bytes: usize,
};

const DenseSingleIndex = struct {
    relations: std.AutoHashMap(TypeRelationKey, DenseSingleRelation),

    fn init(allocator: Allocator) DenseSingleIndex {
        return .{ .relations = std.AutoHashMap(TypeRelationKey, DenseSingleRelation).init(allocator) };
    }

    fn deinit(self: *DenseSingleIndex, allocator: Allocator) void {
        self.clear(allocator);
        self.relations.deinit();
    }

    fn clear(self: *DenseSingleIndex, allocator: Allocator) void {
        var it = self.relations.iterator();
        while (it.next()) |entry| allocator.free(entry.value_ptr.entries);
        self.relations.clearRetainingCapacity();
    }

    fn lookup(self: *const DenseSingleIndex, object_type: u32, object_id: u32, relation: u32) ?DenseEntry {
        const dense = self.relations.get(.{ .object_type = object_type, .relation = relation }) orelse return null;
        if (object_id >= dense.entries.len) return null;
        const entry = dense.entries[object_id];
        if (entry.subject_type == 0) return null;
        return entry;
    }

    fn contains(self: *const DenseSingleIndex, tuple: NumericTuple) bool {
        if (tuple.subject_relation != 0) return false;
        const entry = self.lookup(tuple.object_type, tuple.object_id, tuple.relation) orelse return false;
        return entry.subject_type == tuple.subject_type and entry.subject_id == tuple.subject_id;
    }

    fn stats(self: *const DenseSingleIndex) DenseSingleIndexStats {
        var entries: usize = 0;
        var populated: usize = 0;
        var it = self.relations.iterator();
        while (it.next()) |entry| {
            entries += entry.value_ptr.entries.len;
            populated += entry.value_ptr.count;
        }
        return .{
            .relations = self.relations.count(),
            .entries = entries,
            .populated = populated,
            .estimated_bytes = self.relations.count() * (@sizeOf(TypeRelationKey) + @sizeOf(DenseSingleRelation)) + entries * @sizeOf(DenseEntry),
        };
    }
};

const IndexRange = struct {
    start: usize = 0,
    len: usize = 0,
};

const ForwardIndex = struct {
    buckets: std.AutoHashMap(ObjectRelationKey, IndexRange),
    entries: std.ArrayList(usize),

    fn init(allocator: Allocator) ForwardIndex {
        return .{
            .buckets = std.AutoHashMap(ObjectRelationKey, IndexRange).init(allocator),
            .entries = .empty,
        };
    }

    fn deinit(self: *ForwardIndex, allocator: Allocator) void {
        self.buckets.deinit();
        self.entries.deinit(allocator);
    }

    fn clearRetainingCapacity(self: *ForwardIndex) void {
        self.buckets.clearRetainingCapacity();
        self.entries.clearRetainingCapacity();
    }

    fn ensureBucketCapacity(self: *ForwardIndex, count: usize) !void {
        try self.buckets.ensureTotalCapacity(@intCast(count));
    }

    fn lookup(self: *const ForwardIndex, key: ObjectRelationKey) ?[]const usize {
        const range = self.buckets.get(key) orelse return null;
        return self.entries.items[range.start .. range.start + range.len];
    }

    fn stats(self: *const ForwardIndex) ForwardIndexStats {
        const buckets = self.buckets.count();
        const entries = self.entries.items.len;
        return .{
            .buckets = buckets,
            .entries = entries,
            .estimated_bytes = buckets * (@sizeOf(ObjectRelationKey) + @sizeOf(IndexRange)) + entries * @sizeOf(usize),
        };
    }
};

const ForwardIndexStats = struct {
    buckets: usize,
    entries: usize,
    estimated_bytes: usize,
};

const CombinedForwardIndexStats = struct {
    direct: ForwardIndexStats,
    userset: ForwardIndexStats,

    fn buckets(self: CombinedForwardIndexStats) usize {
        return self.direct.buckets + self.userset.buckets;
    }

    fn entries(self: CombinedForwardIndexStats) usize {
        return self.direct.entries + self.userset.entries;
    }

    fn estimatedBytes(self: CombinedForwardIndexStats) usize {
        return self.direct.estimated_bytes + self.userset.estimated_bytes;
    }
};

const EvalMemoKey = [6]u64;
const eval_key_permission: u64 = 1;
const eval_key_relation: u64 = 2;
const memo_estimated_bytes_per_entry: usize = @sizeOf(EvalMemoKey) + @sizeOf(bool) + 32;

fn evalMemoKey(kind: u64, subject: NumericSubject, object: NumericObject, term: u32) EvalMemoKey {
    return .{
        kind,
        subject.object.typ,
        subject.object.id,
        object.typ,
        object.id,
        term,
    };
}

fn compareNumericTuple(a: NumericTuple, b: NumericTuple) i8 {
    if (a.object_type != b.object_type) return if (a.object_type < b.object_type) -1 else 1;
    if (a.object_id != b.object_id) return if (a.object_id < b.object_id) -1 else 1;
    if (a.relation != b.relation) return if (a.relation < b.relation) -1 else 1;
    if (a.subject_type != b.subject_type) return if (a.subject_type < b.subject_type) -1 else 1;
    if (a.subject_id != b.subject_id) return if (a.subject_id < b.subject_id) -1 else 1;
    if (a.subject_relation != b.subject_relation) return if (a.subject_relation < b.subject_relation) -1 else 1;
    return 0;
}

fn numericTupleLessThan(_: void, a: NumericTuple, b: NumericTuple) bool {
    return compareNumericTuple(a, b) < 0;
}

fn sameObjectRelation(a: NumericTuple, b: NumericTuple) bool {
    return a.object_type == b.object_type and a.object_id == b.object_id and a.relation == b.relation;
}

const BatchResult = struct {
    revision: u64,
    allowed: u64,
    denied: u64,
    failed_closed: u64,
    stats: Stats,
};

const CheckWorker = struct {
    engine: *Engine,
    io: std.Io,
    items: []const CheckItem,
    latencies: []u64,
    offset: usize,
    allowed: u64 = 0,
    denied: u64 = 0,
    failed_closed: u64 = 0,
    stats: Stats = .{},
    memo_entries: usize = 0,
    memo_estimated_bytes: usize = 0,
    completed: *std.atomic.Value(usize),
    err: ?anyerror = null,
};

const ForwardIndexBuildWorker = struct {
    engine: *const Engine,
    start: usize,
    end: usize,
    counts: std.AutoHashMap(ObjectRelationKey, usize),
    entries: ?[]usize = null,
    err: ?anyerror = null,
};

fn runCheckWorker(worker: *CheckWorker) void {
    const allocator = std.heap.smp_allocator;
    var batch_memo = std.AutoHashMap(EvalMemoKey, bool).init(allocator);
    defer batch_memo.deinit();

    for (worker.items, 0..) |item, local_idx| {
        const item_start = std.Io.Clock.awake.now(worker.io);
        const check_result = worker.engine.checkNoProofWithBatchMemo(allocator, item.subject, item.object, item.permission, &batch_memo) catch |err| {
            worker.err = err;
            return;
        };
        worker.latencies[worker.offset + local_idx] = elapsedNs(item_start, std.Io.Clock.awake.now(worker.io));

        switch (check_result.decision) {
            .allowed => worker.allowed += 1,
            .denied => worker.denied += 1,
            .failed_closed => worker.failed_closed += 1,
        }
        worker.stats.add(check_result.stats);
        _ = worker.completed.fetchAdd(1, .monotonic);
    }

    worker.memo_entries = batch_memo.count();
    worker.memo_estimated_bytes = worker.memo_entries * memo_estimated_bytes_per_entry;
}

fn runForwardIndexCountWorker(worker: *ForwardIndexBuildWorker) void {
    var idx = worker.start;
    while (idx < worker.end) : (idx += 1) {
        const tuple = worker.engine.tuple_values.items[idx];
        if (tuple.subject_relation == 0) continue;
        const key = ObjectRelationKey{
            .object_type = tuple.object_type,
            .object_id = tuple.object_id,
            .relation = tuple.relation,
        };
        const entry = worker.counts.getOrPut(key) catch |err| {
            worker.err = err;
            return;
        };
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
    }
}

fn runForwardIndexFillWorker(worker: *ForwardIndexBuildWorker) void {
    const entries = worker.entries.?;
    var idx = worker.start;
    while (idx < worker.end) : (idx += 1) {
        const tuple = worker.engine.tuple_values.items[idx];
        if (tuple.subject_relation == 0) continue;
        const key = ObjectRelationKey{
            .object_type = tuple.object_type,
            .object_id = tuple.object_id,
            .relation = tuple.relation,
        };
        const next = worker.counts.getPtr(key) orelse continue;
        entries[next.*] = idx;
        next.* += 1;
    }
}

pub const Engine = struct {
    allocator: Allocator,
    schema: Schema,
    types: Dictionary,
    object_ids: ObjectIdDictionaries,
    relations: Dictionary,
    traversal_relations: std.AutoHashMap(u32, void),
    tuples: std.AutoHashMap(NumericTuple, usize),
    tuple_values: std.ArrayList(NumericTuple),
    exact_lookup_sorted: bool = false,
    dense_single_index: DenseSingleIndex,
    direct_forward_index: ForwardIndex,
    userset_forward_index: ForwardIndex,
    revision: u64 = 0,
    max_depth: u32 = 64,

    pub fn init(allocator: Allocator) Engine {
        return .{
            .allocator = allocator,
            .schema = Schema.init(allocator),
            .types = Dictionary.init(allocator),
            .object_ids = ObjectIdDictionaries.init(allocator),
            .relations = Dictionary.init(allocator),
            .traversal_relations = std.AutoHashMap(u32, void).init(allocator),
            .tuples = std.AutoHashMap(NumericTuple, usize).init(allocator),
            .tuple_values = .empty,
            .dense_single_index = DenseSingleIndex.init(allocator),
            .direct_forward_index = ForwardIndex.init(allocator),
            .userset_forward_index = ForwardIndex.init(allocator),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.schema.deinit();
        self.dense_single_index.deinit(self.allocator);
        self.direct_forward_index.deinit(self.allocator);
        self.userset_forward_index.deinit(self.allocator);
        self.tuples.deinit();
        self.tuple_values.deinit(self.allocator);
        self.traversal_relations.deinit();
        self.relations.deinit();
        self.object_ids.deinit();
        self.types.deinit();
    }

    pub fn writeSchema(self: *Engine, text: []const u8) !u64 {
        var next = try parseSchema(self.allocator, text);
        errdefer next.deinit();
        try validateSchema(&next);

        self.schema.deinit();
        self.schema = next;
        try self.internSchemaSymbols();
        try self.rebuildTraversalRelations();
        self.revision += 1;
        self.schema.version = self.revision;
        return self.revision;
    }

    pub fn writeRelationship(self: *Engine, tuple_text: []const u8) !u64 {
        const tuple = try parseTuple(tuple_text);
        try self.validateTuple(tuple);
        const key = (try self.numericTuple(tuple, .create)).?;
        const idx = self.tuple_values.items.len;
        try self.tuples.putNoClobber(key, idx);
        try self.tuple_values.append(self.allocator, key);
        self.exact_lookup_sorted = false;
        try self.rebuildForwardIndex();
        self.revision += 1;
        return self.revision;
    }

    fn reserveRelationships(self: *Engine, count: usize) !void {
        try self.tuple_values.ensureTotalCapacity(self.allocator, count);
        try self.direct_forward_index.ensureBucketCapacity(@max(1, count / 4));
        try self.userset_forward_index.ensureBucketCapacity(@max(1, count / 8));
    }

    fn writeNumericRelationship(self: *Engine, key: NumericTuple) !void {
        self.tuple_values.appendAssumeCapacity(key);
        self.exact_lookup_sorted = false;
        self.revision += 1;
    }

    pub fn deleteRelationship(self: *Engine, tuple_text: []const u8) !u64 {
        const tuple = try parseTuple(tuple_text);
        if (try self.numericTuple(tuple, .lookup)) |key| {
            if (self.tuples.fetchRemove(key)) |removed| {
                const idx = removed.value;
                const last_idx = self.tuple_values.items.len - 1;
                if (idx != last_idx) {
                    const moved = self.tuple_values.items[last_idx];
                    self.tuple_values.items[idx] = moved;
                    if (self.tuples.getPtr(moved)) |moved_idx| moved_idx.* = idx;
                }
                _ = self.tuple_values.pop();
                try self.rebuildForwardIndex();
            }
        }
        self.revision += 1;
        return self.revision;
    }

    pub fn check(self: *Engine, subject_text: []const u8, object_text: []const u8, permission: []const u8) !CheckResult {
        return self.checkWithAllocator(self.allocator, subject_text, object_text, permission, true, null);
    }

    fn checkNoProof(self: *Engine, allocator: Allocator, subject_text: []const u8, object_text: []const u8, permission: []const u8) !CheckResult {
        return self.checkWithAllocator(allocator, subject_text, object_text, permission, false, null);
    }

    fn checkNoProofWithBatchMemo(
        self: *Engine,
        allocator: Allocator,
        subject_text: []const u8,
        object_text: []const u8,
        permission: []const u8,
        batch_memo: *std.AutoHashMap(EvalMemoKey, bool),
    ) !CheckResult {
        return self.checkWithAllocator(allocator, subject_text, object_text, permission, false, batch_memo);
    }

    fn checkWithAllocator(
        self: *Engine,
        allocator: Allocator,
        subject_text: []const u8,
        object_text: []const u8,
        permission: []const u8,
        emit_proof: bool,
        batch_memo: ?*std.AutoHashMap(EvalMemoKey, bool),
    ) !CheckResult {
        const subject_text_object = try parseObject(subject_text);
        const object_text_object = try parseObject(object_text);

        const typ = self.schema.getType(object_text_object.typ) orelse return error.UnknownType;
        if (!typ.permissions.contains(permission)) return error.CheckTargetMustBePermission;

        const object_type = self.types.get(object_text_object.typ) orelse return deniedCheckResult(self.revision);
        const object_id = self.object_ids.get(object_type, object_text_object.id) orelse return deniedCheckResult(self.revision);
        const subject_type = self.types.get(subject_text_object.typ) orelse return deniedCheckResult(self.revision);
        const subject_id = self.object_ids.get(subject_type, subject_text_object.id) orelse return deniedCheckResult(self.revision);
        const permission_id = self.relations.get(permission) orelse return deniedCheckResult(self.revision);

        return self.checkNumericWithAllocator(
            allocator,
            .{ .object = .{ .typ = subject_type, .id = subject_id } },
            .{ .typ = object_type, .id = object_id },
            permission_id,
            emit_proof,
            batch_memo,
        );
    }

    fn checkNumericNoProof(
        self: *Engine,
        allocator: Allocator,
        subject: NumericSubject,
        object: NumericObject,
        permission: u32,
        batch_memo: *std.AutoHashMap(EvalMemoKey, bool),
    ) !CheckResult {
        return self.checkNumericWithAllocator(allocator, subject, object, permission, false, batch_memo);
    }

    fn checkNumericWithAllocator(
        self: *Engine,
        allocator: Allocator,
        subject: NumericSubject,
        object: NumericObject,
        permission: u32,
        emit_proof: bool,
        batch_memo: ?*std.AutoHashMap(EvalMemoKey, bool),
    ) !CheckResult {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var local_memo = std.AutoHashMap(EvalMemoKey, bool).init(a);
        defer if (batch_memo == null) local_memo.deinit();

        var ctx = EvalContext{
            .engine = self,
            .allocator = a,
            .stats = .{},
            .visited = std.AutoHashMap(EvalMemoKey, void).init(a),
            .memo = batch_memo orelse &local_memo,
            .proof = std.ArrayList([]const u8).empty,
            .emit_proof = emit_proof,
        };
        defer ctx.visited.deinit();
        defer ctx.proof.deinit(a);

        const object_type_name = self.types.name(object.typ);
        const permission_name = self.relations.name(permission);
        const typ = self.schema.getType(object_type_name) orelse return error.UnknownType;
        if (!typ.permissions.contains(permission_name)) return error.CheckTargetMustBePermission;

        const allowed = evalPermission(&ctx, subject, object, permission, 0) catch |err| switch (err) {
            error.EvalLimitExceeded, error.CycleDetected => {
                return .{
                    .decision = .failed_closed,
                    .revision = self.revision,
                    .stats = ctx.stats,
                };
            },
            else => return err,
        };

        var proof_text: ?[]const u8 = null;
        if (emit_proof and allowed and ctx.proof.items.len > 0) {
            proof_text = try std.mem.join(self.allocator, " -> ", ctx.proof.items);
        }

        return .{
            .decision = if (allowed) .allowed else .denied,
            .revision = self.revision,
            .proof = proof_text,
            .stats = ctx.stats,
        };
    }

    fn batchCheck(self: *Engine, items: []const CheckItem) !BatchResult {
        var allowed: u64 = 0;
        var denied: u64 = 0;
        var failed_closed: u64 = 0;
        var stats = Stats{};

        for (items) |item| {
            const result = try self.check(item.subject, item.object, item.permission);
            defer if (result.proof) |proof| self.allocator.free(proof);
            switch (result.decision) {
                .allowed => allowed += 1,
                .denied => denied += 1,
                .failed_closed => failed_closed += 1,
            }
            stats.add(result.stats);
        }

        return .{
            .revision = self.revision,
            .allowed = allowed,
            .denied = denied,
            .failed_closed = failed_closed,
            .stats = stats,
        };
    }

    fn explainOne(self: *Engine, subject_text: []const u8, object_text: []const u8, permission: []const u8) !CheckResult {
        return self.check(subject_text, object_text, permission);
    }

    fn validateTuple(self: *Engine, tuple: Tuple) !void {
        const typ = self.schema.getType(tuple.object.typ) orelse return error.UnknownObjectType;
        const rel = typ.relations.get(tuple.relation) orelse return error.TupleTargetMustBeRelation;
        for (rel.allowed.items) |allowed| {
            if (!std.mem.eql(u8, allowed.typ, tuple.subject.object.typ)) continue;
            if (allowed.relation == null and tuple.subject.relation == null) return;
            if (allowed.relation != null and tuple.subject.relation != null and std.mem.eql(u8, allowed.relation.?, tuple.subject.relation.?)) return;
        }
        return error.SubjectNotAllowedByRelation;
    }

    fn hasTuple(self: *Engine, tuple: Tuple) !bool {
        const key = (try self.numericTuple(tuple, .lookup)) orelse return false;
        return self.containsExactTuple(key);
    }

    fn containsExactTuple(self: *const Engine, key: NumericTuple) bool {
        if (self.dense_single_index.contains(key)) return true;
        if (self.exact_lookup_sorted) return self.sortedTupleContains(key);
        return self.tuples.contains(key);
    }

    fn sortedTupleContains(self: *const Engine, key: NumericTuple) bool {
        var low: usize = 0;
        var high: usize = self.tuple_values.items.len;
        while (low < high) {
            const mid = low + (high - low) / 2;
            const cmp = compareNumericTuple(self.tuple_values.items[mid], key);
            if (cmp < 0) {
                low = mid + 1;
            } else if (cmp > 0) {
                high = mid;
            } else {
                return true;
            }
        }
        return false;
    }

    fn prepareBulkExactLookup(self: *Engine) void {
        std.sort.pdq(NumericTuple, self.tuple_values.items, {}, numericTupleLessThan);
        self.tuples.clearAndFree();
        self.exact_lookup_sorted = true;
    }

    fn rebuildForwardIndex(self: *Engine) !void {
        self.dense_single_index.clear(self.allocator);
        self.direct_forward_index.clearRetainingCapacity();
        self.userset_forward_index.clearRetainingCapacity();
        try self.buildDenseSingleIndex();
        try self.buildForwardIndex(&self.direct_forward_index, 0);
        try self.buildForwardIndex(&self.userset_forward_index, 1);
    }

    fn rebuildForwardIndexParallel(self: *Engine, thread_count: usize) !void {
        self.dense_single_index.clear(self.allocator);
        self.direct_forward_index.clearRetainingCapacity();
        self.userset_forward_index.clearRetainingCapacity();
        try self.buildDenseSingleIndex();
        try self.buildForwardIndex(&self.direct_forward_index, 0);
        try self.buildUsersetForwardIndexParallel(@max(1, thread_count));
    }

    fn buildDenseSingleIndex(self: *Engine) !void {
        if (!self.exact_lookup_sorted) return;
        var max_ids = std.AutoHashMap(TypeRelationKey, u32).init(self.allocator);
        defer max_ids.deinit();

        var i: usize = 0;
        while (i < self.tuple_values.items.len) {
            const tuple = self.tuple_values.items[i];
            const start = i;
            i += 1;
            while (i < self.tuple_values.items.len and sameObjectRelation(tuple, self.tuple_values.items[i])) : (i += 1) {}
            if (!self.traversal_relations.contains(tuple.relation)) continue;
            if (tuple.subject_relation != 0 or i - start != 1) continue;

            const type_relation = TypeRelationKey{
                .object_type = tuple.object_type,
                .relation = tuple.relation,
            };
            const max_entry = try max_ids.getOrPut(type_relation);
            if (!max_entry.found_existing) max_entry.value_ptr.* = 0;
            max_entry.value_ptr.* = @max(max_entry.value_ptr.*, tuple.object_id);
        }

        var max_it = max_ids.iterator();
        while (max_it.next()) |entry| {
            const len: usize = @as(usize, entry.value_ptr.*) + 1;
            const entries = try self.allocator.alloc(DenseEntry, len);
            @memset(entries, .{});
            try self.dense_single_index.relations.putNoClobber(entry.key_ptr.*, .{
                .entries = entries,
                .count = 0,
            });
        }

        i = 0;
        while (i < self.tuple_values.items.len) {
            const tuple = self.tuple_values.items[i];
            const start = i;
            i += 1;
            while (i < self.tuple_values.items.len and sameObjectRelation(tuple, self.tuple_values.items[i])) : (i += 1) {}
            if (!self.traversal_relations.contains(tuple.relation)) continue;
            if (tuple.subject_relation != 0 or i - start != 1) continue;
            const type_relation = TypeRelationKey{
                .object_type = tuple.object_type,
                .relation = tuple.relation,
            };
            const dense = self.dense_single_index.relations.getPtr(type_relation).?;
            dense.entries[tuple.object_id] = .{
                .subject_type = tuple.subject_type,
                .subject_id = tuple.subject_id,
            };
            dense.count += 1;
        }
    }

    fn buildForwardIndex(self: *Engine, index: *ForwardIndex, userset: u1) !void {
        for (self.tuple_values.items) |tuple| {
            if ((tuple.subject_relation != 0) != (userset == 1)) continue;
            if (userset == 0 and !self.traversal_relations.contains(tuple.relation)) continue;
            if (userset == 0 and self.dense_single_index.contains(tuple)) continue;
            const key = ObjectRelationKey{
                .object_type = tuple.object_type,
                .object_id = tuple.object_id,
                .relation = tuple.relation,
            };
            const entry = try index.buckets.getOrPut(key);
            if (!entry.found_existing) entry.value_ptr.* = .{};
            entry.value_ptr.len += 1;
        }

        var total: usize = 0;
        var bucket_it = index.buckets.iterator();
        while (bucket_it.next()) |entry| {
            entry.value_ptr.start = total;
            total += entry.value_ptr.len;
            entry.value_ptr.len = 0;
        }

        try index.entries.resize(self.allocator, total);

        for (self.tuple_values.items, 0..) |tuple, idx| {
            if ((tuple.subject_relation != 0) != (userset == 1)) continue;
            if (userset == 0 and !self.traversal_relations.contains(tuple.relation)) continue;
            if (userset == 0 and self.dense_single_index.contains(tuple)) continue;
            const key = ObjectRelationKey{
                .object_type = tuple.object_type,
                .object_id = tuple.object_id,
                .relation = tuple.relation,
            };
            const range = index.buckets.getPtr(key).?;
            index.entries.items[range.start + range.len] = idx;
            range.len += 1;
        }
    }

    fn buildUsersetForwardIndexParallel(self: *Engine, thread_count: usize) !void {
        const workers_len = @max(1, @min(thread_count, self.tuple_values.items.len));
        const workers = try self.allocator.alloc(ForwardIndexBuildWorker, workers_len);
        defer self.allocator.free(workers);
        var threads = try self.allocator.alloc(std.Thread, workers_len);
        defer self.allocator.free(threads);

        const base = self.tuple_values.items.len / workers_len;
        const rem = self.tuple_values.items.len % workers_len;
        var offset: usize = 0;
        for (workers, 0..) |*worker, idx| {
            const len = base + if (idx < rem) @as(usize, 1) else 0;
            worker.* = .{
                .engine = self,
                .start = offset,
                .end = offset + len,
                .counts = std.AutoHashMap(ObjectRelationKey, usize).init(std.heap.smp_allocator),
            };
            threads[idx] = try std.Thread.spawn(.{}, runForwardIndexCountWorker, .{worker});
            offset += len;
        }

        for (threads) |thread| thread.join();
        for (workers) |worker| if (worker.err) |err| return err;

        for (workers) |*worker| {
            var it = worker.counts.iterator();
            while (it.next()) |entry| {
                const target = try self.userset_forward_index.buckets.getOrPut(entry.key_ptr.*);
                if (!target.found_existing) target.value_ptr.* = .{};
                target.value_ptr.len += entry.value_ptr.*;
            }
        }

        var total: usize = 0;
        var bucket_it = self.userset_forward_index.buckets.iterator();
        while (bucket_it.next()) |entry| {
            entry.value_ptr.start = total;
            total += entry.value_ptr.len;
            entry.value_ptr.len = 0;
        }

        try self.userset_forward_index.entries.resize(self.allocator, total);

        for (workers) |*worker| {
            var it = worker.counts.iterator();
            while (it.next()) |entry| {
                const range = self.userset_forward_index.buckets.getPtr(entry.key_ptr.*).?;
                const count = entry.value_ptr.*;
                entry.value_ptr.* = range.start + range.len;
                range.len += count;
            }
            worker.entries = self.userset_forward_index.entries.items;
        }

        for (workers, 0..) |*worker, idx| {
            threads[idx] = try std.Thread.spawn(.{}, runForwardIndexFillWorker, .{worker});
        }
        for (threads) |thread| thread.join();

        for (workers) |*worker| worker.counts.deinit();
    }

    fn lookupDirectForward(self: *const Engine, object_type: u32, object_id: u32, relation: u32) ?[]const usize {
        const key = ObjectRelationKey{
            .object_type = object_type,
            .object_id = object_id,
            .relation = relation,
        };
        return self.direct_forward_index.lookup(key);
    }

    fn lookupUsersetForward(self: *const Engine, object_type: u32, object_id: u32, relation: u32) ?[]const usize {
        const key = ObjectRelationKey{
            .object_type = object_type,
            .object_id = object_id,
            .relation = relation,
        };
        return self.userset_forward_index.lookup(key);
    }

    const DictionaryMode = enum {
        create,
        lookup,
    };

    fn numericTuple(self: *Engine, tuple: Tuple, mode: DictionaryMode) !?NumericTuple {
        const object_type = try self.dictionaryId(&self.types, tuple.object.typ, mode) orelse return null;
        const object_id = try self.objectId(object_type, tuple.object.id, mode) orelse return null;
        const relation = try self.dictionaryId(&self.relations, tuple.relation, mode) orelse return null;
        const subject_type = try self.dictionaryId(&self.types, tuple.subject.object.typ, mode) orelse return null;
        const subject_id = try self.objectId(subject_type, tuple.subject.object.id, mode) orelse return null;
        const subject_relation = if (tuple.subject.relation) |rel|
            try self.dictionaryId(&self.relations, rel, mode) orelse return null
        else
            0;

        return .{
            .object_type = object_type,
            .object_id = object_id,
            .relation = relation,
            .subject_type = subject_type,
            .subject_id = subject_id,
            .subject_relation = subject_relation,
        };
    }

    fn dictionaryId(_: *Engine, dictionary: *Dictionary, name: []const u8, mode: DictionaryMode) !?u32 {
        return switch (mode) {
            .create => try dictionary.getOrPut(name),
            .lookup => dictionary.get(name),
        };
    }

    fn objectId(self: *Engine, type_id: u32, name: []const u8, mode: DictionaryMode) !?u32 {
        return switch (mode) {
            .create => try self.object_ids.getOrPut(type_id, name),
            .lookup => self.object_ids.get(type_id, name),
        };
    }

    fn internSchemaSymbols(self: *Engine) !void {
        var type_it = self.schema.types.iterator();
        while (type_it.next()) |type_entry| {
            _ = try self.types.getOrPut(type_entry.key_ptr.*);

            var relation_it = type_entry.value_ptr.relations.iterator();
            while (relation_it.next()) |relation_entry| {
                _ = try self.relations.getOrPut(relation_entry.key_ptr.*);
            }

            var permission_it = type_entry.value_ptr.permissions.iterator();
            while (permission_it.next()) |permission_entry| {
                _ = try self.relations.getOrPut(permission_entry.key_ptr.*);
            }
        }
    }

    fn rebuildTraversalRelations(self: *Engine) !void {
        self.traversal_relations.clearRetainingCapacity();
        var type_it = self.schema.types.iterator();
        while (type_it.next()) |type_entry| {
            var permission_it = type_entry.value_ptr.permissions.iterator();
            while (permission_it.next()) |permission_entry| {
                try self.collectTraversalRelations(permission_entry.value_ptr.expr);
            }
        }
    }

    fn collectTraversalRelations(self: *Engine, expr: *const Expr) !void {
        switch (expr.*) {
            .ref => {},
            .traversal => |traversal| {
                const relation = self.relations.get(traversal.relation) orelse return error.UnknownTraversalRelation;
                try self.traversal_relations.put(relation, {});
            },
            .union_, .intersection, .difference => |binary| {
                try self.collectTraversalRelations(binary.left);
                try self.collectTraversalRelations(binary.right);
            },
        }
    }

    fn objectFromIds(self: *const Engine, typ: u32, id: u32) Object {
        return .{
            .typ = self.types.name(typ),
            .id = self.object_ids.name(typ, id),
        };
    }

    fn tupleToText(self: *const Engine, allocator: Allocator, tuple: NumericTuple) ![]const u8 {
        const object_typ = self.types.name(tuple.object_type);
        const object_id = self.object_ids.name(tuple.object_type, tuple.object_id);
        const relation = self.relations.name(tuple.relation);
        const subject_typ = self.types.name(tuple.subject_type);
        const subject_id = self.object_ids.name(tuple.subject_type, tuple.subject_id);
        if (tuple.subject_relation != 0) {
            return std.fmt.allocPrint(allocator, "{s}:{s}#{s}@{s}:{s}#{s}", .{
                object_typ,
                object_id,
                relation,
                subject_typ,
                subject_id,
                self.relations.name(tuple.subject_relation),
            });
        }
        return std.fmt.allocPrint(allocator, "{s}:{s}#{s}@{s}:{s}", .{
            object_typ,
            object_id,
            relation,
            subject_typ,
            subject_id,
        });
    }
};

const EvalContext = struct {
    engine: *Engine,
    allocator: Allocator,
    stats: Stats,
    visited: std.AutoHashMap(EvalMemoKey, void),
    memo: *std.AutoHashMap(EvalMemoKey, bool),
    proof: std.ArrayList([]const u8),
    emit_proof: bool,
};

fn evalPermission(ctx: *EvalContext, subject: NumericSubject, object: NumericObject, permission: u32, depth: u32) anyerror!bool {
    if (depth > ctx.engine.max_depth) return error.EvalLimitExceeded;
    ctx.stats.nodes_visited += 1;
    ctx.stats.max_depth = @max(ctx.stats.max_depth, depth);

    const key = evalMemoKey(eval_key_permission, subject, object, permission);
    if (ctx.memo.get(key)) |memoized| {
        ctx.stats.memo_hits += 1;
        return memoized;
    }
    ctx.stats.memo_misses += 1;

    const object_type_name = ctx.engine.types.name(object.typ);
    const permission_name = ctx.engine.relations.name(permission);
    const typ = ctx.engine.schema.getType(object_type_name) orelse return error.UnknownType;
    const perm = typ.permissions.get(permission_name) orelse return error.UnknownPermission;

    const proof_len = ctx.proof.items.len;
    const ok = try evalExpr(ctx, typ, subject, object, perm.expr, depth + 1);
    if (!ok) ctx.proof.shrinkRetainingCapacity(proof_len);
    if (ctx.emit_proof and ok) {
        try ctx.proof.append(ctx.allocator, try std.fmt.allocPrint(ctx.allocator, "{s}:{s}.{s}", .{
            object_type_name,
            ctx.engine.object_ids.name(object.typ, object.id),
            permission_name,
        }));
    }

    try ctx.memo.put(key, ok);
    return ok;
}

fn evalExpr(ctx: *EvalContext, typ: *const TypeDef, subject: NumericSubject, object: NumericObject, expr: *const Expr, depth: u32) anyerror!bool {
    if (depth > ctx.engine.max_depth) return error.EvalLimitExceeded;
    return switch (expr.*) {
        .ref => |name| blk: {
            if (typ.relations.contains(name)) {
                const relation_id = ctx.engine.relations.get(name) orelse return false;
                break :blk try evalRelation(ctx, subject, object, relation_id, depth + 1);
            }
            if (typ.permissions.contains(name)) {
                const permission_id = ctx.engine.relations.get(name) orelse return false;
                break :blk try evalPermission(ctx, subject, object, permission_id, depth + 1);
            }
            return error.UnknownPermissionTerm;
        },
        .traversal => |traversal| blk: {
            const relation_id = ctx.engine.relations.get(traversal.relation) orelse return false;
            const permission_id = ctx.engine.relations.get(traversal.permission) orelse return false;
            break :blk try evalTraversal(ctx, subject, object, relation_id, permission_id, depth + 1);
        },
        .union_ => |binary| blk: {
            const proof_len = ctx.proof.items.len;
            if (try evalExpr(ctx, typ, subject, object, binary.left, depth + 1)) break :blk true;
            ctx.proof.shrinkRetainingCapacity(proof_len);
            if (try evalExpr(ctx, typ, subject, object, binary.right, depth + 1)) break :blk true;
            ctx.proof.shrinkRetainingCapacity(proof_len);
            break :blk false;
        },
        .intersection => |binary| blk: {
            const proof_len = ctx.proof.items.len;
            if (!try evalExpr(ctx, typ, subject, object, binary.left, depth + 1)) {
                ctx.proof.shrinkRetainingCapacity(proof_len);
                break :blk false;
            }
            if (!try evalExpr(ctx, typ, subject, object, binary.right, depth + 1)) {
                ctx.proof.shrinkRetainingCapacity(proof_len);
                break :blk false;
            }
            break :blk true;
        },
        .difference => |binary| blk: {
            const proof_len = ctx.proof.items.len;
            if (!try evalExpr(ctx, typ, subject, object, binary.left, depth + 1)) {
                ctx.proof.shrinkRetainingCapacity(proof_len);
                break :blk false;
            }
            const left_proof_len = ctx.proof.items.len;
            const right_allowed = try evalExpr(ctx, typ, subject, object, binary.right, depth + 1);
            ctx.proof.shrinkRetainingCapacity(left_proof_len);
            if (right_allowed) {
                ctx.proof.shrinkRetainingCapacity(proof_len);
                break :blk false;
            }
            break :blk true;
        },
    };
}

fn evalRelation(ctx: *EvalContext, subject: NumericSubject, object: NumericObject, relation: u32, depth: u32) anyerror!bool {
    if (depth > ctx.engine.max_depth) return error.EvalLimitExceeded;
    ctx.stats.nodes_visited += 1;
    ctx.stats.index_lookups += 1;
    ctx.stats.max_depth = @max(ctx.stats.max_depth, depth);

    const visit_key = evalMemoKey(eval_key_relation, subject, object, relation);
    if (ctx.visited.contains(visit_key)) return error.CycleDetected;
    try ctx.visited.put(visit_key, {});
    defer _ = ctx.visited.remove(visit_key);

    const direct = NumericTuple{
        .object_type = object.typ,
        .object_id = object.id,
        .relation = relation,
        .subject_type = subject.object.typ,
        .subject_id = subject.object.id,
        .subject_relation = subject.relation,
    };
    if (ctx.engine.containsExactTuple(direct)) {
        if (ctx.emit_proof) try ctx.proof.append(ctx.allocator, try ctx.engine.tupleToText(ctx.allocator, direct));
        return true;
    }

    const indexes = ctx.engine.lookupUsersetForward(object.typ, object.id, relation) orelse return false;
    for (indexes) |idx| {
        ctx.stats.edges_scanned += 1;
        const tuple = ctx.engine.tuple_values.items[idx];
        const userset_object = NumericObject{ .typ = tuple.subject_type, .id = tuple.subject_id };
        const nested = try evalRelation(ctx, subject, userset_object, tuple.subject_relation, depth + 1);
        if (nested) {
            if (ctx.emit_proof) try ctx.proof.append(ctx.allocator, try ctx.engine.tupleToText(ctx.allocator, tuple));
            return true;
        }
    }

    return false;
}

fn evalTraversal(ctx: *EvalContext, subject: NumericSubject, object: NumericObject, relation: u32, permission: u32, depth: u32) anyerror!bool {
    if (depth > ctx.engine.max_depth) return error.EvalLimitExceeded;
    ctx.stats.index_lookups += 1;

    if (ctx.engine.dense_single_index.lookup(object.typ, object.id, relation)) |entry| {
        ctx.stats.edges_scanned += 1;
        const ok = try evalPermission(ctx, subject, .{ .typ = entry.subject_type, .id = entry.subject_id }, permission, depth + 1);
        if (ok) {
            if (ctx.emit_proof) try ctx.proof.append(ctx.allocator, try ctx.engine.tupleToText(ctx.allocator, .{
                .object_type = object.typ,
                .object_id = object.id,
                .relation = relation,
                .subject_type = entry.subject_type,
                .subject_id = entry.subject_id,
            }));
            return true;
        }
        return false;
    }

    const indexes = ctx.engine.lookupDirectForward(object.typ, object.id, relation) orelse return false;
    for (indexes) |idx| {
        ctx.stats.edges_scanned += 1;
        const tuple = ctx.engine.tuple_values.items[idx];

        const ok = try evalPermission(ctx, subject, .{ .typ = tuple.subject_type, .id = tuple.subject_id }, permission, depth + 1);
        if (ok) {
            if (ctx.emit_proof) try ctx.proof.append(ctx.allocator, try ctx.engine.tupleToText(ctx.allocator, tuple));
            return true;
        }
    }

    return false;
}

fn parseSchema(allocator: Allocator, text: []const u8) !Schema {
    var schema = Schema.init(allocator);
    errdefer schema.deinit();

    var current_type: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOf(u8, raw_line, "//")) |idx| raw_line[0..idx] else raw_line;
        const line = std.mem.trim(u8, no_comment, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, "}")) {
            current_type = null;
            continue;
        }
        if (std.mem.startsWith(u8, line, "type ")) {
            var rest = std.mem.trim(u8, line["type ".len..], " \t");
            const opens = std.mem.endsWith(u8, rest, "{");
            if (opens) rest = std.mem.trim(u8, rest[0 .. rest.len - 1], " \t");
            const name = try allocator.dupe(u8, rest);
            errdefer allocator.free(name);
            if (schema.types.contains(name)) return error.DuplicateType;
            const key = try allocator.dupe(u8, name);
            try schema.types.put(key, try TypeDef.init(allocator, name));
            current_type = if (opens) schema.types.getPtr(name).?.name else null;
            allocator.free(name);
            continue;
        }

        const type_name = current_type orelse return error.DefinitionOutsideType;
        const typ = schema.getTypeMut(type_name) orelse return error.UnknownType;
        if (std.mem.startsWith(u8, line, "relation ")) {
            try parseRelation(allocator, typ, line["relation ".len..]);
        } else if (std.mem.startsWith(u8, line, "permission ")) {
            try parsePermission(allocator, typ, line["permission ".len..]);
        } else {
            return error.InvalidSchemaLine;
        }
    }

    return schema;
}

fn parseRelation(allocator: Allocator, typ: *TypeDef, text: []const u8) !void {
    const colon = std.mem.indexOfScalar(u8, text, ':') orelse return error.InvalidRelation;
    const name = std.mem.trim(u8, text[0..colon], " \t");
    if (typ.relations.contains(name) or typ.permissions.contains(name)) return error.DuplicateDefinition;

    var rel = RelationDef{
        .name = try allocator.dupe(u8, name),
        .allowed = std.ArrayList(AllowedSubject).empty,
    };
    errdefer rel.deinit(allocator);

    var allowed_it = std.mem.splitScalar(u8, text[colon + 1 ..], '|');
    while (allowed_it.next()) |raw_allowed| {
        const allowed_text = std.mem.trim(u8, raw_allowed, " \t");
        if (allowed_text.len == 0) return error.InvalidRelation;
        if (std.mem.indexOfScalar(u8, allowed_text, '#')) |hash| {
            try rel.allowed.append(allocator, .{
                .typ = try allocator.dupe(u8, allowed_text[0..hash]),
                .relation = try allocator.dupe(u8, allowed_text[hash + 1 ..]),
            });
        } else {
            try rel.allowed.append(allocator, .{
                .typ = try allocator.dupe(u8, allowed_text),
            });
        }
    }

    const key = try allocator.dupe(u8, name);
    try typ.relations.put(key, rel);
}

fn parsePermission(allocator: Allocator, typ: *TypeDef, text: []const u8) !void {
    const eq = std.mem.indexOfScalar(u8, text, '=') orelse return error.InvalidPermission;
    const name = std.mem.trim(u8, text[0..eq], " \t");
    if (typ.relations.contains(name) or typ.permissions.contains(name)) return error.DuplicateDefinition;

    var parser = ExprParser{
        .allocator = allocator,
        .text = text[eq + 1 ..],
    };
    const expr = try parser.parse();
    errdefer {
        expr.deinit(allocator);
        allocator.destroy(expr);
    }

    var perm = PermissionDef{
        .name = try allocator.dupe(u8, name),
        .expr = expr,
    };
    errdefer perm.deinit(allocator);

    const key = try allocator.dupe(u8, name);
    try typ.permissions.put(key, perm);
}

const ExprParser = struct {
    allocator: Allocator,
    text: []const u8,
    pos: usize = 0,

    fn parse(self: *ExprParser) !*Expr {
        const expr = try self.parseUnionDifference();
        self.skipSpace();
        if (self.pos != self.text.len) return error.InvalidPermission;
        return expr;
    }

    fn parseUnionDifference(self: *ExprParser) !*Expr {
        var left = try self.parseIntersection();
        errdefer {
            left.deinit(self.allocator);
            self.allocator.destroy(left);
        }

        while (true) {
            self.skipSpace();
            const op = self.peek() orelse break;
            if (op != '+' and op != '-') break;
            self.pos += 1;

            const right = try self.parseIntersection();
            errdefer {
                right.deinit(self.allocator);
                self.allocator.destroy(right);
            }

            const parent = try self.allocator.create(Expr);
            parent.* = if (op == '+')
                .{ .union_ = .{ .left = left, .right = right } }
            else
                .{ .difference = .{ .left = left, .right = right } };
            left = parent;
        }

        return left;
    }

    fn parseIntersection(self: *ExprParser) !*Expr {
        var left = try self.parsePrimary();
        errdefer {
            left.deinit(self.allocator);
            self.allocator.destroy(left);
        }

        while (true) {
            self.skipSpace();
            if (self.peek() != '&') break;
            self.pos += 1;

            const right = try self.parsePrimary();
            errdefer {
                right.deinit(self.allocator);
                self.allocator.destroy(right);
            }

            const parent = try self.allocator.create(Expr);
            parent.* = .{ .intersection = .{ .left = left, .right = right } };
            left = parent;
        }

        return left;
    }

    fn parsePrimary(self: *ExprParser) !*Expr {
        self.skipSpace();
        const first = try self.parseIdentifier();
        errdefer self.allocator.free(first);

        self.skipSpace();
        if (self.peek() == '.') {
            self.pos += 1;
            const second = try self.parseIdentifier();
            errdefer self.allocator.free(second);
            const expr = try self.allocator.create(Expr);
            expr.* = .{ .traversal = .{ .relation = first, .permission = second } };
            return expr;
        }

        const expr = try self.allocator.create(Expr);
        expr.* = .{ .ref = first };
        return expr;
    }

    fn parseIdentifier(self: *ExprParser) ![]const u8 {
        self.skipSpace();
        const start = self.pos;
        if (start >= self.text.len or !isIdentStart(self.text[start])) return error.InvalidIdentifier;
        self.pos += 1;
        while (self.pos < self.text.len and isIdentContinue(self.text[self.pos])) self.pos += 1;
        return try self.allocator.dupe(u8, self.text[start..self.pos]);
    }

    fn skipSpace(self: *ExprParser) void {
        while (self.pos < self.text.len and (self.text[self.pos] == ' ' or self.text[self.pos] == '\t' or self.text[self.pos] == '\r')) self.pos += 1;
    }

    fn peek(self: *const ExprParser) ?u8 {
        if (self.pos >= self.text.len) return null;
        return self.text[self.pos];
    }
};

fn isIdentStart(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return isIdentStart(c) or (c >= '0' and c <= '9');
}

fn validateSchema(schema: *const Schema) !void {
    var type_it = schema.types.iterator();
    while (type_it.next()) |type_entry| {
        const typ = type_entry.value_ptr;
        var rel_it = typ.relations.iterator();
        while (rel_it.next()) |rel_entry| {
            if (rel_entry.value_ptr.allowed.items.len == 0) return error.EmptyAllowedSubjects;
            for (rel_entry.value_ptr.allowed.items) |allowed| {
                const allowed_type = schema.getType(allowed.typ) orelse return error.UnknownAllowedType;
                if (allowed.relation) |rel_name| {
                    if (!allowed_type.relations.contains(rel_name)) return error.UnknownUsersetRelation;
                }
            }
        }

        var perm_it = typ.permissions.iterator();
        while (perm_it.next()) |perm_entry| {
            try validateExpr(schema, typ, perm_entry.value_ptr.expr);
        }
    }
}

fn validateExpr(schema: *const Schema, typ: *const TypeDef, expr: *const Expr) !void {
    switch (expr.*) {
        .ref => |name| {
            if (!typ.relations.contains(name) and !typ.permissions.contains(name)) return error.UnknownPermissionTerm;
        },
        .traversal => |trav| {
            const relation = typ.relations.get(trav.relation) orelse return error.UnknownTraversalRelation;
            for (relation.allowed.items) |allowed| {
                if (allowed.relation != null) continue;
                const target = schema.getType(allowed.typ) orelse return error.UnknownAllowedType;
                if (!target.permissions.contains(trav.permission)) return error.UnknownTraversalPermission;
            }
        },
        .union_, .intersection, .difference => |binary| {
            try validateExpr(schema, typ, binary.left);
            try validateExpr(schema, typ, binary.right);
        },
    }
}

fn parseObject(text: []const u8) !Object {
    const colon = std.mem.indexOfScalar(u8, text, ':') orelse return error.InvalidObject;
    return .{
        .typ = std.mem.trim(u8, text[0..colon], " \t"),
        .id = std.mem.trim(u8, text[colon + 1 ..], " \t"),
    };
}

fn parseSubject(text: []const u8) !Subject {
    if (std.mem.indexOfScalar(u8, text, '#')) |hash| {
        return .{
            .object = try parseObject(text[0..hash]),
            .relation = std.mem.trim(u8, text[hash + 1 ..], " \t"),
        };
    }
    return .{ .object = try parseObject(text) };
}

fn parseTuple(text: []const u8) !Tuple {
    const at = std.mem.indexOfScalar(u8, text, '@') orelse return error.InvalidTuple;
    const left = text[0..at];
    const hash = std.mem.indexOfScalar(u8, left, '#') orelse return error.InvalidTuple;
    return .{
        .object = try parseObject(left[0..hash]),
        .relation = std.mem.trim(u8, left[hash + 1 ..], " \t"),
        .subject = try parseSubject(text[at + 1 ..]),
    };
}

fn tupleKey(allocator: Allocator, tuple: Tuple) ![]const u8 {
    if (tuple.subject.relation) |subject_relation| {
        return std.fmt.allocPrint(allocator, "{s}:{s}#{s}@{s}:{s}#{s}", .{
            tuple.object.typ,
            tuple.object.id,
            tuple.relation,
            tuple.subject.object.typ,
            tuple.subject.object.id,
            subject_relation,
        });
    }
    return std.fmt.allocPrint(allocator, "{s}:{s}#{s}@{s}:{s}", .{
        tuple.object.typ,
        tuple.object.id,
        tuple.relation,
        tuple.subject.object.typ,
        tuple.subject.object.id,
    });
}

fn decisionText(decision: Decision) []const u8 {
    return switch (decision) {
        .allowed => "allowed",
        .denied => "denied",
        .failed_closed => "failed_closed",
    };
}

fn deniedCheckResult(revision: u64) CheckResult {
    return .{
        .decision = .denied,
        .revision = revision,
        .stats = .{},
    };
}

fn elapsedNs(start: std.Io.Timestamp, end: std.Io.Timestamp) u64 {
    return @intCast(start.durationTo(end).nanoseconds);
}

fn phaseTiming(
    wall_start: std.Io.Timestamp,
    wall_end: std.Io.Timestamp,
    cpu_start: std.Io.Timestamp,
    cpu_end: std.Io.Timestamp,
) PhaseTiming {
    return .{
        .elapsed_ns = elapsedNs(wall_start, wall_end),
        .cpu_ns = elapsedNs(cpu_start, cpu_end),
    };
}

fn throughputPerSec(count: usize, elapsed_ns: u64) u64 {
    if (elapsed_ns == 0) return 0;
    return (count * std.time.ns_per_s) / elapsed_ns;
}

fn asSeconds(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
}

fn asMilliseconds(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
}

fn asMicroseconds(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_us));
}

fn asGib(bytes: usize) f64 {
    return @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(1024 * 1024 * 1024));
}

fn asMib(bytes: usize) f64 {
    return @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(1024 * 1024));
}

fn asMillions(value: u64) f64 {
    return @as(f64, @floatFromInt(value)) / 1_000_000.0;
}

fn ratioPercent(part: u64, total: u64) f64 {
    if (total == 0) return 0;
    return (@as(f64, @floatFromInt(part)) * 100.0) / @as(f64, @floatFromInt(total));
}

fn perCheck(total: u64, checks: usize) f64 {
    if (checks == 0) return 0;
    return @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(checks));
}

fn bucketCount(total: usize, bucket: usize) usize {
    if (bucket >= total) return 0;
    return ((total - 1 - bucket) / 10) + 1;
}

fn latencySummary(latencies: []u64) LatencySummary {
    if (latencies.len == 0) {
        return .{
            .avg_ns = 0,
            .p50_ns = 0,
            .p95_ns = 0,
            .p99_ns = 0,
            .max_ns = 0,
        };
    }

    var total: u64 = 0;
    var max_ns: u64 = 0;
    for (latencies) |latency| {
        total += latency;
        max_ns = @max(max_ns, latency);
    }

    std.sort.pdq(u64, latencies, {}, std.sort.asc(u64));

    return .{
        .avg_ns = total / latencies.len,
        .p50_ns = percentile(latencies, 50),
        .p95_ns = percentile(latencies, 95),
        .p99_ns = percentile(latencies, 99),
        .max_ns = max_ns,
    };
}

fn percentile(sorted: []const u64, pct: usize) u64 {
    if (sorted.len == 0) return 0;
    const idx = ((sorted.len - 1) * pct) / 100;
    return sorted[idx];
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();

    const command = args.next() orelse {
        try printUsage(init.io);
        return;
    };

    if (std.mem.eql(u8, command, "demo")) {
        try runDemo(allocator, init.io);
    } else if (std.mem.eql(u8, command, "load")) {
        try runLoadTest(allocator, init.io, &args);
    } else if (std.mem.eql(u8, command, "load-plan")) {
        try runLoadPlan(init.io, &args);
    } else {
        try printUsage(init.io);
    }
}

fn printUsage(io: std.Io) !void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("usage: veriqik <demo|load [orgs teams groups users documents checks]|load-plan [orgs teams groups users documents checks]>\n", .{});
    try stdout.flush();
}

fn runDemo(allocator: Allocator, io: std.Io) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var engine = Engine.init(allocator);
    defer engine.deinit();

    _ = try engine.writeSchema(demo_schema);
    try writeTuplesFromText(&engine, demo_tuples);

    const before = try engine.explainOne("user:kien", "document:doc1", "view");
    defer if (before.proof) |proof| allocator.free(proof);
    try stdout.print("before_delete decision={s} revision={} proof={?s}\n", .{ decisionText(before.decision), before.revision, before.proof });

    _ = try engine.deleteRelationship("group:eng#member@user:kien");
    const after = try engine.check("user:kien", "document:doc1", "view");
    defer if (after.proof) |proof| allocator.free(proof);
    try stdout.print("after_delete decision={s} revision={}\n", .{ decisionText(after.decision), after.revision });
    try stdout.flush();
}

const LoadIds = struct {
    allocator: Allocator,
    user: []u32,
    group: []u32,
    org: []u32,
    team: []u32,
    folder: []u32,
    document: []u32,
    typ_user: u32,
    typ_group: u32,
    typ_org: u32,
    typ_team: u32,
    typ_folder: u32,
    typ_document: u32,
    rel_member: u32,
    rel_admin_member: u32,
    rel_active_member: u32,
    rel_org: u32,
    rel_parent: u32,
    rel_team: u32,
    rel_view: u32,
    rel_viewer: u32,
    rel_banned: u32,

    fn deinit(self: *LoadIds) void {
        self.allocator.free(self.document);
        self.allocator.free(self.folder);
        self.allocator.free(self.team);
        self.allocator.free(self.org);
        self.allocator.free(self.group);
        self.allocator.free(self.user);
    }
};

fn initLoadIds(allocator: Allocator, engine: *Engine, shape: LoadShape, progress: *LoadProgress) !LoadIds {
    var ids = LoadIds{
        .allocator = allocator,
        .user = &.{},
        .group = &.{},
        .org = &.{},
        .team = &.{},
        .folder = &.{},
        .document = &.{},
        .typ_user = try engine.types.getOrPut("user"),
        .typ_group = try engine.types.getOrPut("group"),
        .typ_org = try engine.types.getOrPut("org"),
        .typ_team = try engine.types.getOrPut("team"),
        .typ_folder = try engine.types.getOrPut("folder"),
        .typ_document = try engine.types.getOrPut("document"),
        .rel_member = try engine.relations.getOrPut("member"),
        .rel_admin_member = try engine.relations.getOrPut("admin_member"),
        .rel_active_member = try engine.relations.getOrPut("active_member"),
        .rel_org = try engine.relations.getOrPut("org"),
        .rel_parent = try engine.relations.getOrPut("parent"),
        .rel_team = try engine.relations.getOrPut("team"),
        .rel_view = try engine.relations.getOrPut("view"),
        .rel_viewer = try engine.relations.getOrPut("viewer"),
        .rel_banned = try engine.relations.getOrPut("banned"),
    };
    errdefer ids.deinit();

    var completed: usize = 0;
    ids.user = try internLoadObjectIds(allocator, engine, ids.typ_user, "u", shape.users, &completed, progress);
    ids.group = try internLoadObjectIds(allocator, engine, ids.typ_group, "g", shape.groups, &completed, progress);
    ids.org = try internLoadObjectIds(allocator, engine, ids.typ_org, "o", shape.orgs, &completed, progress);
    ids.team = try internLoadObjectIds(allocator, engine, ids.typ_team, "t", shape.teams, &completed, progress);
    ids.folder = try internLoadObjectIds(allocator, engine, ids.typ_folder, "f", shape.folders, &completed, progress);
    ids.document = try internLoadObjectIds(allocator, engine, ids.typ_document, "d", shape.documents, &completed, progress);
    try progress.report("intern_ids", completed, engine.tuple_values.items.len, true);

    return ids;
}

fn internLoadObjectIds(
    allocator: Allocator,
    engine: *Engine,
    type_id: u32,
    prefix: []const u8,
    count: usize,
    completed: *usize,
    progress: *LoadProgress,
) ![]u32 {
    const ids = try allocator.alloc(u32, count);
    errdefer allocator.free(ids);

    const dictionary = try engine.object_ids.ensureType(type_id);
    try dictionary.ids.ensureTotalCapacity(@intCast(count));
    try dictionary.names.ensureTotalCapacity(engine.allocator, count);

    for (ids, 0..) |*id, idx| {
        const name = try std.fmt.allocPrint(engine.allocator, "{s}{}", .{ prefix, idx });
        id.* = try engine.object_ids.putNewOwnedAssumeCapacity(type_id, name);
        completed.* += 1;
        try progress.report("intern_ids", completed.*, engine.tuple_values.items.len, false);
    }

    return ids;
}

fn generateLoadRelationships(engine: *Engine, shape: LoadShape, ids: LoadIds, progress_offset: usize, progress: *LoadProgress, index_threads: usize) !void {
    try engine.reserveRelationships(shape.estimatedTuples());
    try progress.report("reserve_tuples", progress_offset, engine.tuple_values.items.len, true);

    var i: usize = 0;
    while (i < shape.users) : (i += 1) {
        var f: usize = 0;
        while (f < shape.user_group_fanout) : (f += 1) {
            try engine.writeNumericRelationship(.{
                .object_type = ids.typ_group,
                .object_id = ids.group[(i + f) % shape.groups],
                .relation = ids.rel_member,
                .subject_type = ids.typ_user,
                .subject_id = ids.user[i],
            });
            try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);
        }
    }

    var g: usize = 1;
    while (g < shape.groups) : (g += 1) {
        const parent_group = if (g % load_group_chain_depth == 0) 0 else g - 1;
        try engine.writeNumericRelationship(.{
            .object_type = ids.typ_group,
            .object_id = ids.group[g],
            .relation = ids.rel_member,
            .subject_type = ids.typ_group,
            .subject_id = ids.group[parent_group],
            .subject_relation = ids.rel_member,
        });
        try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);
    }

    g = 0;
    while (g < shape.groups) : (g += 1) {
        const active_user = loadActiveUserForOrg(shape, g % shape.orgs, 1);
        try engine.writeNumericRelationship(.{
            .object_type = ids.typ_group,
            .object_id = ids.group[g],
            .relation = ids.rel_member,
            .subject_type = ids.typ_user,
            .subject_id = ids.user[active_user],
        });
        try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);
    }

    var o: usize = 0;
    while (o < shape.orgs) : (o += 1) {
        const admin_user = loadActiveUserForOrg(shape, o, 1);
        try engine.writeNumericRelationship(.{
            .object_type = ids.typ_org,
            .object_id = ids.org[o],
            .relation = ids.rel_admin_member,
            .subject_type = ids.typ_user,
            .subject_id = ids.user[admin_user],
        });
        try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);

        var f: usize = 0;
        while (f < shape.org_admin_fanout) : (f += 1) {
            try engine.writeNumericRelationship(.{
                .object_type = ids.typ_org,
                .object_id = ids.org[o],
                .relation = ids.rel_admin_member,
                .subject_type = ids.typ_group,
                .subject_id = ids.group[(o + f) % shape.groups],
                .subject_relation = ids.rel_member,
            });
            try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);
        }

        f = 0;
        while (f < shape.org_active_fanout) : (f += 1) {
            const active_user = (o * shape.org_active_fanout + f) % shape.users;
            try engine.writeNumericRelationship(.{
                .object_type = ids.typ_org,
                .object_id = ids.org[o],
                .relation = ids.rel_active_member,
                .subject_type = ids.typ_user,
                .subject_id = ids.user[active_user],
            });
            try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);
        }
    }

    var t: usize = 0;
    while (t < shape.teams) : (t += 1) {
        try engine.writeNumericRelationship(.{
            .object_type = ids.typ_team,
            .object_id = ids.team[t],
            .relation = ids.rel_org,
            .subject_type = ids.typ_org,
            .subject_id = ids.org[t % shape.orgs],
        });
        try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);

        const team_member_user = loadActiveUserForOrg(shape, t % shape.orgs, 1);
        try engine.writeNumericRelationship(.{
            .object_type = ids.typ_team,
            .object_id = ids.team[t],
            .relation = ids.rel_member,
            .subject_type = ids.typ_user,
            .subject_id = ids.user[team_member_user],
        });
        try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);

        var f: usize = 0;
        while (f < shape.team_group_fanout) : (f += 1) {
            try engine.writeNumericRelationship(.{
                .object_type = ids.typ_team,
                .object_id = ids.team[t],
                .relation = ids.rel_member,
                .subject_type = ids.typ_group,
                .subject_id = ids.group[(t + f) % shape.groups],
                .subject_relation = ids.rel_member,
            });
            try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);
        }
    }

    var folder: usize = 0;
    while (folder < shape.folders) : (folder += 1) {
        if (folder > 0) {
            const parent_folder = (folder - 1) / load_folder_parent_fanout;
            try engine.writeNumericRelationship(.{
                .object_type = ids.typ_folder,
                .object_id = ids.folder[folder],
                .relation = ids.rel_parent,
                .subject_type = ids.typ_folder,
                .subject_id = ids.folder[parent_folder],
            });
            try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);
        }

        try engine.writeNumericRelationship(.{
            .object_type = ids.typ_folder,
            .object_id = ids.folder[folder],
            .relation = ids.rel_team,
            .subject_type = ids.typ_team,
            .subject_id = ids.team[folder % shape.teams],
        });
        try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);

        const folder_viewer_user = loadActiveUserForOrg(shape, folder % shape.orgs, 1);
        try engine.writeNumericRelationship(.{
            .object_type = ids.typ_folder,
            .object_id = ids.folder[folder],
            .relation = ids.rel_viewer,
            .subject_type = ids.typ_user,
            .subject_id = ids.user[folder_viewer_user],
        });
        try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);

        var f: usize = 0;
        while (f < shape.folder_viewer_fanout) : (f += 1) {
            try engine.writeNumericRelationship(.{
                .object_type = ids.typ_folder,
                .object_id = ids.folder[folder],
                .relation = ids.rel_viewer,
                .subject_type = ids.typ_group,
                .subject_id = ids.group[(folder + f) % shape.groups],
                .subject_relation = ids.rel_member,
            });
            try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);
        }
    }

    var d: usize = 0;
    while (d < shape.documents) : (d += 1) {
        try engine.writeNumericRelationship(.{
            .object_type = ids.typ_document,
            .object_id = ids.document[d],
            .relation = ids.rel_parent,
            .subject_type = ids.typ_folder,
            .subject_id = ids.folder[d % shape.folders],
        });
        try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);

        try engine.writeNumericRelationship(.{
            .object_type = ids.typ_document,
            .object_id = ids.document[d],
            .relation = ids.rel_team,
            .subject_type = ids.typ_team,
            .subject_id = ids.team[d % shape.teams],
        });
        try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);

        try engine.writeNumericRelationship(.{
            .object_type = ids.typ_document,
            .object_id = ids.document[d],
            .relation = ids.rel_org,
            .subject_type = ids.typ_org,
            .subject_id = ids.org[d % shape.orgs],
        });
        try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);

        var f: usize = 0;
        while (f < shape.document_viewer_fanout) : (f += 1) {
            try engine.writeNumericRelationship(.{
                .object_type = ids.typ_document,
                .object_id = ids.document[d],
                .relation = ids.rel_viewer,
                .subject_type = ids.typ_group,
                .subject_id = ids.group[(d + f) % shape.groups],
                .subject_relation = ids.rel_member,
            });
            try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);
        }

        f = 0;
        while (f < shape.document_direct_viewer_fanout) : (f += 1) {
            const viewer_user = loadActiveUser(shape, d, f);
            try engine.writeNumericRelationship(.{
                .object_type = ids.typ_document,
                .object_id = ids.document[d],
                .relation = ids.rel_viewer,
                .subject_type = ids.typ_user,
                .subject_id = ids.user[viewer_user],
            });
            try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);
        }

        var b: usize = 0;
        while (b < shape.banned_fanout) : (b += 1) {
            const banned_user = if (b == 0 and isLoadBannedCaseDocument(d)) loadActiveUser(shape, d, 0) else (d + b) % shape.users;
            try engine.writeNumericRelationship(.{
                .object_type = ids.typ_document,
                .object_id = ids.document[d],
                .relation = ids.rel_banned,
                .subject_type = ids.typ_user,
                .subject_id = ids.user[banned_user],
            });
            try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, false);
        }
    }
    try progress.report("write_tuples", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, true);
    engine.prepareBulkExactLookup();
    try engine.rebuildForwardIndexParallel(index_threads);
    try progress.report("build_indexes", progress_offset + engine.tuple_values.items.len, engine.tuple_values.items.len, true);
}

fn isLoadBannedCaseDocument(document: usize) bool {
    return document % 5 == 0;
}

fn loadCheckDocument(shape: LoadShape, seed: usize, want_banned_case: bool) usize {
    var document = (seed * 17) % shape.documents;
    if (want_banned_case) {
        const remainder = document % 5;
        if (remainder != 0) document += 5 - remainder;
        if (document >= shape.documents) document = 0;
    } else if (isLoadBannedCaseDocument(document)) {
        document = (document + 1) % shape.documents;
    }
    return document;
}

fn loadCheckDocumentForModulo(shape: LoadShape, seed: usize, modulo: usize, want_banned_case: bool) usize {
    const bounded_modulo = @max(1, @min(modulo, shape.documents));
    const object = seed % bounded_modulo;
    var document = object;
    while (document < shape.documents) : (document += bounded_modulo) {
        if (isLoadBannedCaseDocument(document) == want_banned_case) return document;
    }
    return object;
}

fn loadCheckDocumentForModuloAndOrg(shape: LoadShape, seed: usize, modulo: usize, org: usize, want_banned_case: bool) usize {
    const bounded_modulo = @max(1, @min(modulo, shape.documents));
    const object = seed % bounded_modulo;
    var document = object;
    while (document < shape.documents) : (document += bounded_modulo) {
        if (document % shape.orgs == org and isLoadBannedCaseDocument(document) == want_banned_case) return document;
    }
    return object;
}

fn loadActiveUserForOrg(shape: LoadShape, org: usize, offset: usize) usize {
    return (org * shape.org_active_fanout + (offset % shape.org_active_fanout)) % shape.users;
}

fn loadActiveUser(shape: LoadShape, document: usize, offset: usize) usize {
    return loadActiveUserForOrg(shape, document % shape.orgs, offset);
}

fn loadDeniedUser(shape: LoadShape, document: usize) usize {
    const active_user = loadActiveUser(shape, document, 0);
    const step = if (shape.org_active_fanout < shape.users) shape.org_active_fanout else 1;
    var user = (active_user + @max(1, step)) % shape.users;
    if (user == active_user and shape.users > 1) user = (active_user + 1) % shape.users;
    return user;
}

fn runLoadTest(allocator: Allocator, io: std.Io, args: *std.process.Args.Iterator) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const shape = try nextLoadShape(args, .{
        .orgs = 2,
        .teams = 10,
        .groups = 10,
        .users = 50,
        .documents = 50,
        .checks = 1000,
    });

    const estimated_tuples = shape.estimatedTuples();
    const estimated_bytes = shape.estimatedBytes();
    if (estimated_bytes > load_memory_budget_bytes) {
        try stdout.print(
            \\load_refused orgs={} teams={} groups={} users={} documents={} checks={}
            \\estimated_tuples={}
            \\estimated_tuple_storage_bytes={}
            \\estimated_dictionary_bytes={}
            \\estimated_check_bytes={}
            \\estimated_bytes={}
            \\memory_budget_bytes={}
            \\memory_budget_ceiling_bytes={}
            \\hint=use load-plan for sizing, or pass smaller synced load parameters
            \\
        , .{
            shape.orgs,
            shape.teams,
            shape.groups,
            shape.users,
            shape.documents,
            shape.checks,
            estimated_tuples,
            shape.estimatedTupleStorageBytes(),
            shape.estimatedDictionaryBytes(),
            shape.estimatedCheckBytes(),
            estimated_bytes,
            load_memory_budget_bytes,
            load_memory_budget_bytes,
        });
        try stdout.flush();
        return;
    }
    try validateNumericLoadShape(shape);

    var metered = MeteredAllocator.init(allocator);
    const load_allocator = metered.allocator();
    var progress = LoadProgress.init(io, &metered, loadProgressTotal(shape));
    try progress.report("start", 0, 0, true);

    const build_wall_start = std.Io.Clock.awake.now(io);
    const build_cpu_start = std.Io.Clock.cpu_process.now(io);

    var engine = Engine.init(load_allocator);
    defer engine.deinit();
    engine.max_depth = load_max_depth;

    _ = try engine.writeSchema(load_schema);
    try progress.report("schema", 0, engine.tuple_values.items.len, true);
    var load_ids = try initLoadIds(load_allocator, &engine, shape, &progress);
    defer load_ids.deinit();
    const id_progress = shape.estimatedDictionaryNames();
    const index_threads = @max(1, std.Thread.getCpuCount() catch 1);
    try generateLoadRelationships(&engine, shape, load_ids, id_progress, &progress, index_threads);

    var items = try std.ArrayList(CheckItem).initCapacity(load_allocator, shape.checks);
    defer {
        for (items.items) |item| {
            load_allocator.free(item.subject);
            load_allocator.free(item.object);
        }
        items.deinit(load_allocator);
    }

    var c: usize = 0;
    while (c < shape.checks) : (c += 1) {
        const bucket = c % 10;
        const group_object = c % @max(1, @min(shape.orgs, shape.groups));
        const folder_object = c % shape.folders;
        const team_object = c % shape.teams;
        const org_object = c % shape.orgs;
        const document = switch (bucket) {
            0, 1 => loadCheckDocument(shape, c, false),
            2 => loadCheckDocumentForModuloAndOrg(shape, group_object, shape.groups, group_object % shape.orgs, false),
            3 => loadCheckDocumentForModuloAndOrg(shape, folder_object, shape.folders, folder_object % shape.orgs, false),
            4 => loadCheckDocumentForModuloAndOrg(shape, team_object, shape.teams, team_object % shape.orgs, false),
            5 => loadCheckDocumentForModuloAndOrg(shape, org_object, shape.orgs, org_object, false),
            6 => loadCheckDocument(shape, c, true),
            else => loadCheckDocument(shape, c, false),
        };
        const user = switch (bucket) {
            0, 1, 6 => loadActiveUser(shape, document, 0),
            2 => loadActiveUserForOrg(shape, document % shape.groups % shape.orgs, 1),
            3 => loadActiveUserForOrg(shape, document % shape.folders % shape.orgs, 1),
            4 => loadActiveUserForOrg(shape, document % shape.teams % shape.orgs, 1),
            5 => loadActiveUserForOrg(shape, document % shape.orgs, 1),
            else => loadDeniedUser(shape, document),
        };
        try items.append(load_allocator, .{
            .subject = try std.fmt.allocPrint(load_allocator, "user:u{}", .{user}),
            .object = try std.fmt.allocPrint(load_allocator, "document:d{}", .{document}),
            .permission = "view",
        });
    }
    try progress.report("checks_generated", loadProgressTotal(shape), engine.tuple_values.items.len, true);

    const build_timing = phaseTiming(
        build_wall_start,
        std.Io.Clock.awake.now(io),
        build_cpu_start,
        std.Io.Clock.cpu_process.now(io),
    );

    const latencies = try load_allocator.alloc(u64, shape.checks);
    defer load_allocator.free(latencies);
    @memset(latencies, 0);

    const check_wall_start = std.Io.Clock.awake.now(io);
    const check_cpu_start = std.Io.Clock.cpu_process.now(io);
    const check_threads = @max(1, @min(shape.checks, std.Thread.getCpuCount() catch 1));
    var completed_checks = std.atomic.Value(usize).init(0);
    const workers = try load_allocator.alloc(CheckWorker, check_threads);
    defer load_allocator.free(workers);
    const threads = try load_allocator.alloc(std.Thread, check_threads);
    defer load_allocator.free(threads);

    const base = shape.checks / check_threads;
    const rem = shape.checks % check_threads;
    var offset: usize = 0;
    for (workers, 0..) |*worker, idx| {
        const len = base + if (idx < rem) @as(usize, 1) else 0;
        worker.* = .{
            .engine = &engine,
            .io = io,
            .items = items.items[offset .. offset + len],
            .latencies = latencies,
            .offset = offset,
            .completed = &completed_checks,
        };
        threads[idx] = try std.Thread.spawn(.{}, runCheckWorker, .{worker});
        offset += len;
    }

    var check_progress = LoadProgress.init(io, &metered, shape.checks);
    while (completed_checks.load(.monotonic) < shape.checks) {
        try check_progress.report("checks", completed_checks.load(.monotonic), engine.tuple_values.items.len, false);
        std.Io.sleep(io, std.Io.Duration.fromMilliseconds(100), .awake) catch {};
    }

    for (threads) |thread| thread.join();
    try check_progress.report("checks", completed_checks.load(.monotonic), engine.tuple_values.items.len, true);

    const check_timing = phaseTiming(
        check_wall_start,
        std.Io.Clock.awake.now(io),
        check_cpu_start,
        std.Io.Clock.cpu_process.now(io),
    );

    var result = BatchResult{
        .revision = engine.revision,
        .allowed = 0,
        .denied = 0,
        .failed_closed = 0,
        .stats = .{},
    };
    var memo_entries_total: usize = 0;
    var memo_entries_max_worker: usize = 0;
    var memo_estimated_bytes_total: usize = 0;
    var memo_estimated_bytes_max_worker: usize = 0;
    for (workers) |worker| {
        if (worker.err) |err| return err;
        result.allowed += worker.allowed;
        result.denied += worker.denied;
        result.failed_closed += worker.failed_closed;
        result.stats.add(worker.stats);
        memo_entries_total += worker.memo_entries;
        memo_entries_max_worker = @max(memo_entries_max_worker, worker.memo_entries);
        memo_estimated_bytes_total += worker.memo_estimated_bytes;
        memo_estimated_bytes_max_worker = @max(memo_estimated_bytes_max_worker, worker.memo_estimated_bytes);
    }

    const latency = latencySummary(latencies);
    const checks_per_sec = throughputPerSec(shape.checks, check_timing.elapsed_ns);
    const tuples_per_sec_build = throughputPerSec(engine.tuple_values.items.len, build_timing.elapsed_ns);
    const bytes_per_sec_estimated = throughputPerSec(estimated_bytes, build_timing.elapsed_ns);
    const index_stats = CombinedForwardIndexStats{
        .direct = engine.direct_forward_index.stats(),
        .userset = engine.userset_forward_index.stats(),
    };
    const dense_stats = engine.dense_single_index.stats();
    const exact_lookup_estimated_bytes = engine.tuple_values.items.len * @sizeOf(NumericTuple);

    try stdout.print("load_test users={} groups={} documents={} tuples={} checks={}\n", .{
        shape.users,
        shape.groups,
        shape.documents,
        engine.tuple_values.items.len,
        shape.checks,
    });
    try stdout.print("execution_model optimize={s} load_threads=1 index_threads={} check_threads={} storage=core_numeric_tuples object_id_space=per_type_u32 tuples_materialized=yes ingest=bulk_numeric_generated tuple_lookup=sorted_tuple_values index=compact_userset_forward+dense_single_traversal index_build=parallel_userset check_path=public_string batch_memo=per_worker_after_decode\n", .{
        @tagName(builtin.mode),
        index_threads,
        check_threads,
    });
    try stdout.print("shape orgs={} teams={} folders={} user_group_fanout={} org_active_fanout={} team_group_fanout={} folder_parent_fanout={} folder_viewer_fanout={} document_viewer_fanout={} document_direct_viewer_fanout={} banned_fanout={}\n", .{
        shape.orgs,
        shape.teams,
        shape.folders,
        shape.user_group_fanout,
        shape.org_active_fanout,
        shape.team_group_fanout,
        load_folder_parent_fanout,
        shape.folder_viewer_fanout,
        shape.document_viewer_fanout,
        shape.document_direct_viewer_fanout,
        shape.banned_fanout,
    });
    try stdout.print("check_mix direct_allowed={} document_group_allowed={} parent_allowed={} team_allowed={} org_admin_allowed={} banned_denied={} other_denied={}\n", .{
        bucketCount(shape.checks, 0) + bucketCount(shape.checks, 1),
        bucketCount(shape.checks, 2),
        bucketCount(shape.checks, 3),
        bucketCount(shape.checks, 4),
        bucketCount(shape.checks, 5),
        bucketCount(shape.checks, 6),
        bucketCount(shape.checks, 7) + bucketCount(shape.checks, 8) + bucketCount(shape.checks, 9),
    });
    try stdout.print("memory estimated_bytes={} allocated_current_bytes={} allocated_peak_bytes={} alloc_count={} free_count={}\n", .{
        estimated_bytes,
        metered.allocated_current_bytes,
        metered.allocated_peak_bytes,
        metered.alloc_count,
        metered.free_count,
    });
    try stdout.print("tuple_lookup mode={s} tuple_hash_entries={} sorted_entries={} sorted_estimated_bytes={} tuple_bytes_per_entry={}\n", .{
        if (engine.exact_lookup_sorted) "sorted_tuple_values" else "hash_map",
        engine.tuples.count(),
        engine.tuple_values.items.len,
        exact_lookup_estimated_bytes,
        @sizeOf(NumericTuple),
    });
    try stdout.print("index_sizes direct_buckets={} direct_entries={} direct_estimated_bytes={} userset_buckets={} userset_entries={} userset_estimated_bytes={} total_buckets={} total_entries={} total_estimated_bytes={}\n", .{
        index_stats.direct.buckets,
        index_stats.direct.entries,
        index_stats.direct.estimated_bytes,
        index_stats.userset.buckets,
        index_stats.userset.entries,
        index_stats.userset.estimated_bytes,
        index_stats.buckets(),
        index_stats.entries(),
        index_stats.estimatedBytes(),
    });
    try stdout.print("dense_indexes relations={} entries={} populated={} estimated_bytes={}\n", .{
        dense_stats.relations,
        dense_stats.entries,
        dense_stats.populated,
        dense_stats.estimated_bytes,
    });
    try stdout.print("build_phase elapsed_ns={} cpu_ns={} tuples_per_sec={} bytes_per_sec_estimated={}\n", .{
        build_timing.elapsed_ns,
        build_timing.cpu_ns,
        tuples_per_sec_build,
        bytes_per_sec_estimated,
    });
    try stdout.print("check_phase elapsed_ns={} cpu_ns={} checks_per_sec={}\n", .{
        check_timing.elapsed_ns,
        check_timing.cpu_ns,
        checks_per_sec,
    });
    try stdout.print("latency avg_ns={} p50_ns={} p95_ns={} p99_ns={} max_ns={}\n", .{
        latency.avg_ns,
        latency.p50_ns,
        latency.p95_ns,
        latency.p99_ns,
        latency.max_ns,
    });
    try stdout.print("result allowed={} denied={} failed_closed={} revision={}\n", .{
        result.allowed,
        result.denied,
        result.failed_closed,
        engine.revision,
    });
    try stdout.print("stats nodes_visited={} edges_scanned={} index_lookups={} memo_hits={} memo_misses={} max_depth={}\n", .{
        result.stats.nodes_visited,
        result.stats.edges_scanned,
        result.stats.index_lookups,
        result.stats.memo_hits,
        result.stats.memo_misses,
        result.stats.max_depth,
    });
    try stdout.print("memo entries_total={} entries_max_worker={} estimated_bytes_total={} estimated_bytes_max_worker={} estimated_bytes_per_entry={} scope=per_worker allocator=smp_allocator\n", .{
        memo_entries_total,
        memo_entries_max_worker,
        memo_estimated_bytes_total,
        memo_estimated_bytes_max_worker,
        memo_estimated_bytes_per_entry,
    });
    try stdout.print("summary\n", .{});
    try stdout.print("  dataset users={} groups={} documents={} tuples={} checks={}\n", .{
        shape.users,
        shape.groups,
        shape.documents,
        engine.tuple_values.items.len,
        shape.checks,
    });
    try stdout.print("  memory estimated={d:.2}GiB current={d:.2}GiB peak={d:.2}GiB\n", .{
        asGib(estimated_bytes),
        asGib(metered.allocated_current_bytes),
        asGib(metered.allocated_peak_bytes),
    });
    try stdout.print("  indexes total={d:.2}GiB buckets={} entries={} direct={d:.2}GiB/{d:.2}M entries userset={d:.2}GiB/{d:.2}M entries\n", .{
        asGib(index_stats.estimatedBytes()),
        index_stats.buckets(),
        index_stats.entries(),
        asGib(index_stats.direct.estimated_bytes),
        @as(f64, @floatFromInt(index_stats.direct.entries)) / 1_000_000.0,
        asGib(index_stats.userset.estimated_bytes),
        @as(f64, @floatFromInt(index_stats.userset.entries)) / 1_000_000.0,
    });
    try stdout.print("  dense_indexes relations={} populated={} estimated={d:.2}GiB dense_slots={} tuple_lookup={s} tuple_hash_entries={}\n", .{
        dense_stats.relations,
        dense_stats.populated,
        asGib(dense_stats.estimated_bytes),
        dense_stats.entries,
        if (engine.exact_lookup_sorted) "sorted_tuple_values" else "hash_map",
        engine.tuples.count(),
    });
    try stdout.print("  build elapsed={d:.2}s cpu={d:.2}s throughput={d:.2}M tuples/s estimated_bytes={d:.2}GiB/s\n", .{
        asSeconds(build_timing.elapsed_ns),
        asSeconds(build_timing.cpu_ns),
        asMillions(tuples_per_sec_build),
        asGib(bytes_per_sec_estimated),
    });
    try stdout.print("  checks elapsed={d:.2}s cpu={d:.2}s throughput={d:.2}K checks/s threads={}\n", .{
        asSeconds(check_timing.elapsed_ns),
        asSeconds(check_timing.cpu_ns),
        @as(f64, @floatFromInt(checks_per_sec)) / 1_000.0,
        check_threads,
    });
    try stdout.print("  latency avg={d:.2}us p50={d:.2}us p95={d:.2}us p99={d:.2}us max={d:.2}ms\n", .{
        asMicroseconds(latency.avg_ns),
        asMicroseconds(latency.p50_ns),
        asMicroseconds(latency.p95_ns),
        asMicroseconds(latency.p99_ns),
        asMilliseconds(latency.max_ns),
    });
    try stdout.print("  decisions allowed={d:.1}% ({}) denied={d:.1}% ({}) failed_closed={}\n", .{
        ratioPercent(result.allowed, shape.checks),
        result.allowed,
        ratioPercent(result.denied, shape.checks),
        result.denied,
        result.failed_closed,
    });
    try stdout.print("  check_mix direct_allowed={} document_group_allowed={} parent_allowed={} team_allowed={} org_admin_allowed={} banned_denied={} other_denied={}\n", .{
        bucketCount(shape.checks, 0) + bucketCount(shape.checks, 1),
        bucketCount(shape.checks, 2),
        bucketCount(shape.checks, 3),
        bucketCount(shape.checks, 4),
        bucketCount(shape.checks, 5),
        bucketCount(shape.checks, 6),
        bucketCount(shape.checks, 7) + bucketCount(shape.checks, 8) + bucketCount(shape.checks, 9),
    });
    try stdout.print("  graph_work nodes/check={d:.1} edges/check={d:.1} index_lookups/check={d:.1} memo_hit_rate={d:.1}% max_depth={}\n", .{
        perCheck(result.stats.nodes_visited, shape.checks),
        perCheck(result.stats.edges_scanned, shape.checks),
        perCheck(result.stats.index_lookups, shape.checks),
        ratioPercent(result.stats.memo_hits, result.stats.memo_hits + result.stats.memo_misses),
        result.stats.max_depth,
    });
    try stdout.print("  memo scope=per_worker entries={} max_worker_entries={} estimated={d:.2}GiB max_worker={d:.2}MiB hit_rate={d:.1}%\n", .{
        memo_entries_total,
        memo_entries_max_worker,
        asGib(memo_estimated_bytes_total),
        asMib(memo_estimated_bytes_max_worker),
        ratioPercent(result.stats.memo_hits, result.stats.memo_hits + result.stats.memo_misses),
    });
    try stdout.flush();
}

const LoadShape = struct {
    orgs: usize,
    teams: usize,
    users: usize,
    groups: usize,
    documents: usize,
    folders: usize,
    checks: usize,
    user_group_fanout: usize,
    org_admin_fanout: usize,
    org_active_fanout: usize,
    team_group_fanout: usize,
    folder_viewer_fanout: usize,
    document_viewer_fanout: usize,
    document_direct_viewer_fanout: usize,
    banned_fanout: usize,

    fn fromPlan(orgs: usize, teams: usize, groups: usize, users: usize, documents: usize, checks: usize) LoadShape {
        return .{
            .orgs = orgs,
            .teams = teams,
            .users = users,
            .groups = groups,
            .documents = documents,
            .folders = @max(1, @min(load_max_folders, documents / load_documents_per_folder)),
            .checks = checks,
            .user_group_fanout = @min(groups, 4),
            .org_admin_fanout = @min(groups, 3),
            .org_active_fanout = @max(1, users / orgs),
            .team_group_fanout = @min(groups, 4),
            .folder_viewer_fanout = @min(groups, 3),
            .document_viewer_fanout = @min(groups, 4),
            .document_direct_viewer_fanout = @min(users, 1),
            .banned_fanout = @min(users, 1),
        };
    }

    fn estimatedTuples(self: LoadShape) usize {
        return self.users * self.user_group_fanout +
            (self.groups - 1) + self.groups +
            self.orgs * (1 + self.org_admin_fanout + self.org_active_fanout) +
            self.teams * (2 + self.team_group_fanout) +
            (self.folders - 1) + self.folders * (2 + self.folder_viewer_fanout) +
            self.documents * (3 + self.document_viewer_fanout + self.document_direct_viewer_fanout + self.banned_fanout);
    }

    fn estimatedTupleStorageBytes(self: LoadShape) usize {
        return self.estimatedTuples() * tuple_storage_bytes_per_tuple_estimate;
    }

    fn estimatedDictionaryNames(self: LoadShape) usize {
        return self.orgs + self.teams + self.groups + self.users + self.documents + self.folders + 16;
    }

    fn estimatedDictionaryBytes(self: LoadShape) usize {
        return self.estimatedDictionaryNames() * dictionary_bytes_per_name_estimate;
    }

    fn estimatedCheckBytes(self: LoadShape) usize {
        return self.checks * check_bytes_per_item_estimate;
    }

    fn estimatedBytes(self: LoadShape) usize {
        return load_fixed_bytes_estimate +
            self.estimatedTupleStorageBytes() +
            self.estimatedDictionaryBytes() +
            self.estimatedCheckBytes();
    }

    fn fitToMemory(self: LoadShape, budget_bytes: usize) LoadShape {
        var lo: usize = 1;
        var hi: usize = self.documents;
        var best: usize = 1;

        while (lo <= hi) {
            const mid = lo + (hi - lo) / 2;
            const candidate = LoadShape.fromPlan(self.orgs, self.teams, self.groups, self.users, mid, @min(self.checks, mid * 10));
            if (candidate.estimatedBytes() <= budget_bytes) {
                best = mid;
                lo = mid + 1;
            } else if (mid == 0) {
                break;
            } else {
                hi = mid - 1;
            }
        }

        return LoadShape.fromPlan(self.orgs, self.teams, self.groups, self.users, best, @min(self.checks, best * 10));
    }
};

const LoadShapeDefaults = struct {
    orgs: usize,
    teams: usize,
    groups: usize,
    users: usize,
    documents: usize,
    checks: usize,
};

fn nextLoadShape(args: *std.process.Args.Iterator, defaults: LoadShapeDefaults) !LoadShape {
    const orgs = try nextUsize(args, defaults.orgs);
    const teams = try nextUsize(args, defaults.teams);
    const groups = try nextUsize(args, defaults.groups);
    const users = try nextUsize(args, defaults.users);
    const documents = try nextUsize(args, defaults.documents);
    const checks = try nextUsize(args, defaults.checks);
    if (orgs == 0 or teams == 0 or groups == 0 or users == 0 or documents == 0 or checks == 0) return error.InvalidLoadShape;
    return LoadShape.fromPlan(orgs, teams, groups, users, documents, checks);
}

fn validateNumericLoadShape(shape: LoadShape) !void {
    const max_u32: usize = std.math.maxInt(u32);
    if (shape.orgs > max_u32 or
        shape.teams > max_u32 or
        shape.groups > max_u32 or
        shape.users > max_u32 or
        shape.documents > max_u32)
    {
        return error.NumericLoadShapeTooLarge;
    }
}

fn runLoadPlan(io: std.Io, args: *std.process.Args.Iterator) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const shape = try nextLoadShape(args, .{
        .orgs = 1000,
        .teams = 100_000,
        .groups = 100_000,
        .users = 1_000_000,
        .documents = 10_000_000,
        .checks = 1_000_000,
    });
    const estimated_tuples = shape.estimatedTuples();
    const estimated_bytes = shape.estimatedBytes();
    const fit_budget = shape.fitToMemory(load_memory_budget_bytes);

    try stdout.print("load_plan orgs={} teams={} users={} groups={} folders={} documents={} checks={}\n", .{
        shape.orgs,
        shape.teams,
        shape.users,
        shape.groups,
        shape.folders,
        shape.documents,
        shape.checks,
    });
    try stdout.print("fanout user_group={} org_admin={} org_active={} team_group={} folder_parent={} folder_viewer={} document_viewer={} document_direct_viewer={} banned={}\n", .{
        shape.user_group_fanout,
        shape.org_admin_fanout,
        shape.org_active_fanout,
        shape.team_group_fanout,
        load_folder_parent_fanout,
        shape.folder_viewer_fanout,
        shape.document_viewer_fanout,
        shape.document_direct_viewer_fanout,
        shape.banned_fanout,
    });
    try stdout.print("estimated_tuples={}\nestimated_tuple_storage_bytes={}\nestimated_dictionary_names={}\n", .{
        estimated_tuples,
        shape.estimatedTupleStorageBytes(),
        shape.estimatedDictionaryNames(),
    });
    try stdout.print("estimated_dictionary_bytes={}\nestimated_check_bytes={}\nestimated_bytes={}\nmemory_budget_bytes={}\nmemory_budget_ceiling_bytes={}\n", .{
        shape.estimatedDictionaryBytes(),
        shape.estimatedCheckBytes(),
        estimated_bytes,
        load_memory_budget_bytes,
        load_memory_budget_bytes,
    });
    try stdout.print("estimate_constants tuple_storage_bytes_per_tuple={} dictionary_bytes_per_name={} check_bytes_per_item={} fixed_bytes={}\n", .{
        tuple_storage_bytes_per_tuple_estimate,
        dictionary_bytes_per_name_estimate,
        check_bytes_per_item_estimate,
        load_fixed_bytes_estimate,
    });
    try stdout.print("planned_command=zig build run -- load-plan {} {} {} {} {} {}\n", .{
        shape.orgs,
        shape.teams,
        shape.groups,
        shape.users,
        shape.documents,
        shape.checks,
    });
    try stdout.print("load_command=zig build run -- load {} {} {} {} {} {}\n", .{
        shape.orgs,
        shape.teams,
        shape.groups,
        shape.users,
        shape.documents,
        shape.checks,
    });
    try stdout.print("load_fast_command=zig build run-fast -- load {} {} {} {} {} {}\n", .{
        shape.orgs,
        shape.teams,
        shape.groups,
        shape.users,
        shape.documents,
        shape.checks,
    });
    try stdout.print("load_budget_command=zig build run -- load {} {} {} {} {} {}\n", .{
        fit_budget.orgs,
        fit_budget.teams,
        fit_budget.groups,
        fit_budget.users,
        fit_budget.documents,
        fit_budget.checks,
    });
    try stdout.print("load_budget_fast_command=zig build run-fast -- load {} {} {} {} {} {}\n", .{
        fit_budget.orgs,
        fit_budget.teams,
        fit_budget.groups,
        fit_budget.users,
        fit_budget.documents,
        fit_budget.checks,
    });
    try stdout.print("load_budget_estimated_tuples={}\nload_budget_estimated_bytes={}\nnote this is a conservative sizing target; measured load output is authoritative\n", .{
        fit_budget.estimatedTuples(),
        fit_budget.estimatedBytes(),
    });
    try stdout.flush();
}

fn nextUsize(args: *std.process.Args.Iterator, default: usize) !usize {
    const raw = args.next() orelse return default;
    return std.fmt.parseInt(usize, raw, 10);
}

fn writeTuplesFromText(engine: *Engine, text: []const u8) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "#")) continue;
        _ = try engine.writeRelationship(line);
    }
}
