const std = @import("std");

const max_line_length = 100;
const max_source_file_size = 16 * 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;
    const cwd = std.Io.Dir.cwd();

    var violations: usize = 0;
    violations += try check_file(allocator, io, cwd, "build.zig");
    violations += try check_file(allocator, io, cwd, "build.zig.zon");
    violations += try check_directory(allocator, io, cwd, "src");
    violations += try check_directory(allocator, io, cwd, "tools");

    if (violations > 0) {
        std.debug.print("TigerStyle violations: {d}\n", .{violations});
        return error.TigerStyleViolation;
    }
}

fn check_directory(
    allocator: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    path: []const u8,
) !usize {
    var directory = try cwd.openDir(io, path, .{ .iterate = true });
    defer directory.close(io);

    var walker = try directory.walk(allocator);
    var violations: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".zig")) continue;

        const display_path = try std.fs.path.join(allocator, &.{ path, entry.path });
        violations += try check_file_at(allocator, io, directory, entry.path, display_path);
    }
    return violations;
}

fn check_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    directory: std.Io.Dir,
    path: []const u8,
) !usize {
    return check_file_at(allocator, io, directory, path, path);
}

fn check_file_at(
    allocator: std.mem.Allocator,
    io: std.Io,
    directory: std.Io.Dir,
    path: []const u8,
    display_path: []const u8,
) !usize {
    const source = try directory.readFileAlloc(
        io,
        path,
        allocator,
        .limited(max_source_file_size),
    );
    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_number: usize = 1;
    var violations: usize = 0;
    while (lines.next()) |line| : (line_number += 1) {
        if (line.len <= max_line_length) continue;

        std.debug.print("{s}:{d}:{d}: line exceeds {d} columns\n", .{
            display_path,
            line_number,
            max_line_length + 1,
            max_line_length,
        });
        violations += 1;
    }
    return violations;
}
