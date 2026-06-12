const std = @import("std");
const app = @import("main.zig");

const test_operators_schema = @embedFile("fixtures/tests/operators/schema.vq");
const test_operators_tuples = @embedFile("fixtures/tests/operators/tuples.txt");
const test_operators_checks = @embedFile("fixtures/tests/operators/checks.txt");
const test_traversal_usersets_schema = @embedFile("fixtures/tests/traversal_usersets/schema.vq");
const test_traversal_usersets_tuples = @embedFile("fixtures/tests/traversal_usersets/tuples.txt");
const test_traversal_usersets_checks = @embedFile("fixtures/tests/traversal_usersets/checks.txt");
const test_cycles_schema = @embedFile("fixtures/tests/cycles/schema.vq");
const test_cycles_tuples = @embedFile("fixtures/tests/cycles/tuples.txt");
const test_cycles_checks = @embedFile("fixtures/tests/cycles/checks.txt");

const CheckFixture = struct {
    name: []const u8,
    schema: []const u8,
    tuples: []const u8,
    checks: []const u8,
};

fn writeTuplesFromText(engine: *app.Engine, text: []const u8) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "#")) continue;
        _ = try engine.writeRelationship(line);
    }
}

fn expectedDecision(raw: []const u8) !app.Decision {
    if (std.mem.eql(u8, raw, "allowed")) return .allowed;
    if (std.mem.eql(u8, raw, "denied")) return .denied;
    if (std.mem.eql(u8, raw, "failed_closed")) return .failed_closed;
    return error.UnknownExpectedDecision;
}

fn runCheckFixture(fixture: CheckFixture) !void {
    const allocator = std.testing.allocator;
    var engine = app.Engine.init(allocator);
    defer engine.deinit();

    _ = try engine.writeSchema(fixture.schema);
    try writeTuplesFromText(&engine, fixture.tuples);

    var line_no: usize = 0;
    var lines = std.mem.splitScalar(u8, fixture.checks, '\n');
    while (lines.next()) |raw_line| {
        line_no += 1;
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "#")) continue;

        var parts = std.mem.tokenizeScalar(u8, line, ' ');
        const expected_raw = parts.next() orelse return error.InvalidCheckFixture;
        const subject = parts.next() orelse return error.InvalidCheckFixture;
        const object = parts.next() orelse return error.InvalidCheckFixture;
        const permission = parts.next() orelse return error.InvalidCheckFixture;
        try std.testing.expectEqual(@as(?[]const u8, null), parts.next());

        const result = try engine.check(subject, object, permission);
        defer if (result.proof) |proof| allocator.free(proof);
        const expected = try expectedDecision(expected_raw);
        std.testing.expectEqual(expected, result.decision) catch |err| {
            std.debug.print("fixture={s} line={} expected={s} subject={s} object={s} permission={s}\n", .{
                fixture.name,
                line_no,
                expected_raw,
                subject,
                object,
                permission,
            });
            return err;
        };
    }
}

test "fixture-backed DSL and check engine semantics" {
    const fixtures = [_]CheckFixture{
        .{
            .name = "operators",
            .schema = test_operators_schema,
            .tuples = test_operators_tuples,
            .checks = test_operators_checks,
        },
        .{
            .name = "traversal_usersets",
            .schema = test_traversal_usersets_schema,
            .tuples = test_traversal_usersets_tuples,
            .checks = test_traversal_usersets_checks,
        },
        .{
            .name = "cycles",
            .schema = test_cycles_schema,
            .tuples = test_cycles_tuples,
            .checks = test_cycles_checks,
        },
    };

    for (fixtures) |fixture| try runCheckFixture(fixture);
}

test "public checks reject relation targets" {
    const allocator = std.testing.allocator;
    var engine = app.Engine.init(allocator);
    defer engine.deinit();

    _ = try engine.writeSchema(
        \\type user
        \\type document {
        \\  relation viewer: user
        \\  permission view = viewer
        \\}
    );
    try std.testing.expectError(error.CheckTargetMustBePermission, engine.check("user:kien", "document:doc1", "viewer"));
}

test "public checks support same raw object id across different types" {
    const allocator = std.testing.allocator;
    var engine = app.Engine.init(allocator);
    defer engine.deinit();

    _ = try engine.writeSchema(
        \\type user
        \\type group {
        \\  relation member: user
        \\}
        \\type document {
        \\  relation viewer: user | group#member
        \\  permission view = viewer
        \\}
    );
    _ = try engine.writeRelationship("group:1#member@user:1");
    _ = try engine.writeRelationship("document:1#viewer@group:1#member");

    const result = try engine.check("user:1", "document:1", "view");
    defer if (result.proof) |proof| allocator.free(proof);
    try std.testing.expectEqual(app.Decision.allowed, result.decision);
}

test "delete relationship revokes access and rebuilds indexes" {
    const allocator = std.testing.allocator;
    var engine = app.Engine.init(allocator);
    defer engine.deinit();

    _ = try engine.writeSchema(test_operators_schema);
    _ = try engine.writeRelationship("document:doc1#viewer@user:kien");
    _ = try engine.writeRelationship("document:doc1#active@user:kien");

    const before = try engine.check("user:kien", "document:doc1", "view");
    defer if (before.proof) |proof| allocator.free(proof);
    try std.testing.expectEqual(app.Decision.allowed, before.decision);

    _ = try engine.deleteRelationship("document:doc1#active@user:kien");
    const after = try engine.check("user:kien", "document:doc1", "view");
    defer if (after.proof) |proof| allocator.free(proof);
    try std.testing.expectEqual(app.Decision.denied, after.decision);
}
