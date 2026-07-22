const std = @import("std");

const max_line_length = 100;
const max_function_lines = 70;
const max_source_file_size = 16 * 1024 * 1024;

const excluded_directories = [_][]const u8{
    ".git",
    ".zig-cache",
    "generated",
    "vendor",
    "zig-out",
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;
    const cwd = std.Io.Dir.cwd();

    var violations = try check_zig_files(allocator, io, cwd);
    violations += try check_text_file(allocator, io, cwd, "build.zig.zon");
    if (violations == 0) return;

    std.debug.print("TigerStyle violations: {d}\n", .{violations});
    return error.TigerStyleViolation;
}

fn check_zig_files(
    allocator: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
) !usize {
    var repository = try cwd.openDir(io, ".", .{ .iterate = true });
    defer repository.close(io);

    var walker = try repository.walk(allocator);
    defer walker.deinit();

    var violations: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory and is_excluded_path(entry.path)) {
            walker.leave(io);
            continue;
        }
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".zig")) continue;

        violations += check_filename(entry.path);
        violations += try check_zig_file(allocator, io, repository, entry.path);
    }
    return violations;
}

fn is_excluded_path(path: []const u8) bool {
    var components = std.mem.splitScalar(u8, path, std.fs.path.sep);
    while (components.next()) |component| {
        for (excluded_directories) |excluded| {
            if (std.mem.eql(u8, component, excluded)) return true;
        }
    }
    return false;
}

fn check_filename(path: []const u8) usize {
    const basename = std.fs.path.basename(path);
    if (std.mem.eql(u8, basename, "build.zig")) return 0;

    const stem = basename[0 .. basename.len - ".zig".len];
    if (is_snake_case(stem)) return 0;

    std.debug.print("{s}: filename must use snake_case\n", .{path});
    return 1;
}

fn check_text_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    directory: std.Io.Dir,
    path: []const u8,
) !usize {
    const source = try read_source(allocator, io, directory, path);
    return check_text(source, path);
}

fn check_zig_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    directory: std.Io.Dir,
    path: []const u8,
) !usize {
    const source = try read_source(allocator, io, directory, path);
    var violations = check_text(source, path);

    const source_z = try allocator.dupeZ(u8, source);
    var tree = try std.zig.Ast.parse(allocator, source_z, .zig);
    defer tree.deinit(allocator);
    if (tree.errors.len == 0) violations += try check_ast(allocator, &tree, path);
    return violations;
}

fn read_source(
    allocator: std.mem.Allocator,
    io: std.Io,
    directory: std.Io.Dir,
    path: []const u8,
) ![]const u8 {
    return directory.readFileAlloc(
        io,
        path,
        allocator,
        .limited(max_source_file_size),
    );
}

fn check_text(source: []const u8, path: []const u8) usize {
    var violations: usize = 0;
    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_number: usize = 1;
    while (lines.next()) |line| : (line_number += 1) {
        if (line.len > max_line_length) {
            report(path, line_number, max_line_length + 1, "line exceeds 100 columns");
            violations += 1;
        }
        if (std.mem.indexOfScalar(u8, line, '\t')) |column| {
            report(path, line_number, column + 1, "tab character is not allowed");
            violations += 1;
        }
        if (std.mem.indexOfScalar(u8, line, '\r')) |column| {
            report(path, line_number, column + 1, "line endings must be Unix LF");
            violations += 1;
        }
        if (line.len > 0 and (line[line.len - 1] == ' ' or line[line.len - 1] == '\t')) {
            report(path, line_number, line.len, "trailing whitespace is not allowed");
            violations += 1;
        }
    }
    if (source.len == 0 or source[source.len - 1] != '\n') {
        report(path, line_number - 1, 1, "file must end with a newline");
        violations += 1;
    }
    return violations;
}

fn check_ast(
    allocator: std.mem.Allocator,
    tree: *const std.zig.Ast,
    path: []const u8,
) !usize {
    const node_count = tree.nodes.len;
    const attached_prototypes = try allocator.alloc(bool, node_count);
    @memset(attached_prototypes, false);

    for (0..node_count) |node_number| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(node_number);
        if (tree.nodeTag(node) != .fn_decl) continue;
        const prototype, _ = tree.nodeData(node).node_and_node;
        attached_prototypes[@intFromEnum(prototype)] = true;
    }

    var violations: usize = 0;
    for (0..node_count) |node_number| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(node_number);
        violations += check_node(tree, path, node, attached_prototypes);
    }
    return violations;
}

fn check_node(
    tree: *const std.zig.Ast,
    path: []const u8,
    node: std.zig.Ast.Node.Index,
    attached_prototypes: []const bool,
) usize {
    var violations: usize = 0;
    if (tree.nodeTag(node) == .fn_decl) {
        violations += check_function(tree, path, node);
    } else if (is_function_prototype(tree.nodeTag(node)) and
        !attached_prototypes[@intFromEnum(node)])
    {
        violations += check_function_prototype(tree, path, node);
    }
    if (tree.fullVarDecl(node)) |variable| {
        violations += check_variable(tree, path, variable);
    }
    if (tree.fullContainerField(node)) |field| {
        if (!field.ast.tuple_like) {
            const type_node = field.ast.type_expr.unwrap();
            if (type_node != null and
                std.mem.eql(u8, tree.getNodeSource(type_node.?), "type"))
            {
                violations += check_title_token(tree, path, field.ast.main_token);
            } else {
                violations += check_snake_token(tree, path, field.ast.main_token, "field");
            }
        }
    }
    violations += check_payloads(tree, path, node);
    return violations;
}

fn is_function_prototype(tag: std.zig.Ast.Node.Tag) bool {
    return switch (tag) {
        .fn_proto, .fn_proto_multi, .fn_proto_one, .fn_proto_simple => true,
        else => false,
    };
}

fn check_function(
    tree: *const std.zig.Ast,
    path: []const u8,
    node: std.zig.Ast.Node.Index,
) usize {
    const prototype_node, const body = tree.nodeData(node).node_and_node;
    var violations = check_function_prototype(tree, path, prototype_node);

    const first = tree.firstToken(node);
    const last = tree.lastToken(body);
    const first_location = tree.tokenLocation(0, first);
    const last_location = tree.tokenLocation(0, last);
    const line_count = last_location.line - first_location.line + 1;
    if (line_count <= max_function_lines) return violations;

    report(path, first_location.line + 1, first_location.column + 1, "function exceeds 70 lines");
    violations += 1;
    return violations;
}

fn check_function_prototype(
    tree: *const std.zig.Ast,
    path: []const u8,
    node: std.zig.Ast.Node.Index,
) usize {
    var buffer: [1]std.zig.Ast.Node.Index = undefined;
    var prototype = tree.fullFnProto(&buffer, node).?;
    var violations: usize = 0;
    if (prototype.name_token) |name| {
        violations += check_snake_token(tree, path, name, "function");
    }

    var parameters = prototype.iterate(tree);
    while (parameters.next()) |parameter| {
        if (parameter.name_token) |name| {
            violations += check_snake_token(tree, path, name, "parameter");
        }
    }
    return violations;
}

fn check_variable(
    tree: *const std.zig.Ast,
    path: []const u8,
    variable: std.zig.Ast.full.VarDecl,
) usize {
    const name_token = variable.ast.mut_token + 1;
    if (tree.tokenTag(name_token) != .identifier) return 0;

    const is_type = if (variable.ast.type_node.unwrap()) |type_node|
        std.mem.eql(u8, tree.getNodeSource(type_node), "type")
    else if (variable.ast.init_node.unwrap()) |init_node|
        is_type_expression(tree, init_node)
    else
        false;

    if (is_type) return check_title_token(tree, path, name_token);
    return check_snake_token(tree, path, name_token, "variable");
}

fn is_type_expression(tree: *const std.zig.Ast, node: std.zig.Ast.Node.Index) bool {
    return switch (tree.nodeTag(node)) {
        .container_decl,
        .container_decl_trailing,
        .container_decl_two,
        .container_decl_two_trailing,
        .container_decl_arg,
        .container_decl_arg_trailing,
        .tagged_union,
        .tagged_union_trailing,
        .tagged_union_enum_tag,
        .tagged_union_enum_tag_trailing,
        .tagged_union_two,
        .tagged_union_two_trailing,
        => !is_namespace_container(tree, node),
        .error_set_decl,
        .optional_type,
        .array_type,
        .array_type_sentinel,
        .ptr_type_aligned,
        .ptr_type_sentinel,
        .ptr_type,
        .ptr_type_bit_range,
        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        .anyframe_type,
        .error_union,
        => true,
        .identifier, .field_access => is_title_case(tree.tokenSlice(tree.lastToken(node))),
        .call, .call_comma, .call_one, .call_one_comma => {
            var buffer: [1]std.zig.Ast.Node.Index = undefined;
            const call = tree.fullCall(&buffer, node).?;
            return is_type_expression(tree, call.ast.fn_expr);
        },
        else => false,
    };
}

fn is_namespace_container(
    tree: *const std.zig.Ast,
    node: std.zig.Ast.Node.Index,
) bool {
    var buffer: [2]std.zig.Ast.Node.Index = undefined;
    const container = tree.fullContainerDecl(&buffer, node).?;
    if (container.ast.members.len == 0) return false;

    for (container.ast.members) |member| {
        if (tree.fullContainerField(member) != null) return false;
    }
    return true;
}

fn check_payloads(
    tree: *const std.zig.Ast,
    path: []const u8,
    node: std.zig.Ast.Node.Index,
) usize {
    var violations: usize = 0;
    if (tree.fullIf(node)) |conditional| {
        violations += check_optional_payload(tree, path, conditional.payload_token);
        if (conditional.error_token) |token| {
            violations += check_snake_token(tree, path, token, "capture");
        }
    } else if (tree.fullWhile(node)) |loop| {
        violations += check_optional_payload(tree, path, loop.payload_token);
        if (loop.error_token) |token| {
            violations += check_snake_token(tree, path, token, "capture");
        }
    } else if (tree.fullFor(node)) |loop| {
        violations += check_payload(tree, path, loop.payload_token);
    } else if (tree.fullSwitchCase(node)) |case| {
        violations += check_optional_payload(tree, path, case.payload_token);
    } else switch (tree.nodeTag(node)) {
        .@"catch", .@"errdefer" => {
            const keyword = tree.nodeMainToken(node);
            if (tree.tokenTag(keyword + 1) == .pipe) {
                violations += check_payload(tree, path, keyword + 2);
            }
        },
        else => {},
    }
    return violations;
}

fn check_optional_payload(
    tree: *const std.zig.Ast,
    path: []const u8,
    token: ?std.zig.Ast.TokenIndex,
) usize {
    if (token) |payload| return check_payload(tree, path, payload);
    return 0;
}

fn check_payload(
    tree: *const std.zig.Ast,
    path: []const u8,
    first_token: std.zig.Ast.TokenIndex,
) usize {
    var token = first_token;
    var violations: usize = 0;
    while (tree.tokenTag(token) != .pipe) : (token += 1) {
        if (tree.tokenTag(token) == .identifier) {
            violations += check_snake_token(tree, path, token, "capture");
        }
    }
    return violations;
}

fn check_snake_token(
    tree: *const std.zig.Ast,
    path: []const u8,
    token: std.zig.Ast.TokenIndex,
    kind: []const u8,
) usize {
    const name = tree.tokenSlice(token);
    if (is_snake_case(name)) return 0;

    const location = tree.tokenLocation(0, token);
    std.debug.print("{s}:{d}:{d}: {s} '{s}' must use snake_case\n", .{
        path,
        location.line + 1,
        location.column + 1,
        kind,
        name,
    });
    return 1;
}

fn check_title_token(
    tree: *const std.zig.Ast,
    path: []const u8,
    token: std.zig.Ast.TokenIndex,
) usize {
    const name = tree.tokenSlice(token);
    if (is_title_case(name)) return 0;

    const location = tree.tokenLocation(0, token);
    std.debug.print("{s}:{d}:{d}: type '{s}' must use TitleCase\n", .{
        path,
        location.line + 1,
        location.column + 1,
        name,
    });
    return 1;
}

fn is_snake_case(name: []const u8) bool {
    if (std.mem.eql(u8, name, "_")) return true;
    if (name.len == 0 or !std.ascii.isLower(name[0])) return false;

    var previous_underscore = false;
    for (name) |character| {
        if (character == '_') {
            if (previous_underscore) return false;
            previous_underscore = true;
        } else {
            if (!std.ascii.isLower(character) and !std.ascii.isDigit(character)) return false;
            previous_underscore = false;
        }
    }
    return !previous_underscore;
}

fn is_title_case(name: []const u8) bool {
    if (name.len == 0 or !std.ascii.isUpper(name[0])) return false;
    for (name[1..]) |character| {
        if (!std.ascii.isAlphanumeric(character)) return false;
    }
    return true;
}

fn report(
    path: []const u8,
    line: usize,
    column: usize,
    message: []const u8,
) void {
    std.debug.print("{s}:{d}:{d}: {s}\n", .{ path, line, column, message });
}
