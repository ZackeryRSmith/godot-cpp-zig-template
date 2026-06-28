const std = @import("std");

const zcc = @import("compile_commands");
const zon = @import("build.zig.zon");

const extension_name = @tagName(zon.name);

fn findPython(b: *std.Build) ?[]const u8 {
    const candidates = &[_][]const u8{ "python3", "python", "py" };
    for (candidates) |candidate| {
        var process = std.process.spawn(b.graph.io, .{
            .argv = &.{ candidate, "--version" },
        }) catch continue;
        const term = process.wait(b.graph.io) catch continue;
        if (term.exited == 0) {
            return candidate;
        }
    }
    return null;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const allocator = b.allocator;

    const trim_api = b.option(
        bool,
        "trim-api",
        "Only generate/compile bindings for classes listed in build_profile.json (faster builds)",
    ) orelse false;
    const build_profile_path = "build_profile.json";

    var targets: std.ArrayList(*std.Build.Step.Compile) = .empty;
    defer targets.deinit(allocator);

    const cpp_flags = &[_][]const u8{
        "-std=c++17",
        "-fno-exceptions",
    };

    const gen_stamp_path = "extern/godot-cpp/gen/.trim-api-stamp";

    // capture both "trimmed vs full" and the requrested features
    const gen_stamp_contents = if (trim_api) blk: {
        const profile_bytes = b.build_root.handle.readFileAlloc(
            b.graph.io,
            build_profile_path,
            allocator,
            .limited(10 * 1024 * 1024),
        ) catch |err| {
            std.debug.print(
                "Error reading {s}: {any} (required when -Dtrim-api=true)\n",
                .{ build_profile_path, err },
            );
            break :blk b.fmt("trimmed:missing", .{});
        };
        defer allocator.free(profile_bytes);
        var hash: [std.crypto.hash.sha3.Sha3_256.digest_length]u8 = undefined;
        std.crypto.hash.sha3.Sha3_256.hash(profile_bytes, &hash, .{});
        break :blk b.fmt("trimmed:{s}", .{std.fmt.bytesToHex(&hash, .lower)});
    } else b.fmt("full", .{});

    const needs_gen = blk: {
        var dir = b.build_root.handle.openDir(
            b.graph.io,
            "extern/godot-cpp/gen/include/godot_cpp/classes",
            .{ .iterate = true },
        ) catch break :blk true;
        defer dir.close(b.graph.io);
        var it = dir.iterate();
        const first = it.next(b.graph.io) catch break :blk true;
        if (first == null) break :blk true;

        // bindings exist but were they generated with the requested mode and features
        const stamp = b.build_root.handle.readFileAlloc(
            b.graph.io,
            gen_stamp_path,
            allocator,
            .limited(1024),
        ) catch break :blk true;
        defer allocator.free(stamp);
        break :blk !std.mem.eql(u8, stamp, gen_stamp_contents);
    };

    if (needs_gen) {
        const python = findPython(b) orelse {
            std.debug.print(
                \\Error: Python not found. Please install Python 3 and ensure
                \\'python', 'python3', or 'py' is available in your PATH.
                \\This is required to generate godot-cpp bindings.
                \\
            , .{});
            return;
        };

        // wipe stale gen
        b.build_root.handle.deleteTree(b.graph.io, "extern/godot-cpp/gen") catch {};

        const profile_arg = if (trim_api) b.pathFromRoot(build_profile_path) else "";
        const gen_script = b.fmt(
            \\import sys
            \\sys.path.insert(0, r'{s}')
            \\from binding_generator import _generate_bindings
            \\from build_profile import generate_trimmed_api
            \\api = generate_trimmed_api(r'{s}', r'{s}')
            \\_generate_bindings(api, r'{s}', True, '64', 'single', r'{s}')
        ,
            .{
                b.pathFromRoot("extern/godot-cpp"),
                b.pathFromRoot("extern/godot-cpp/gdextension/extension_api.json"),
                profile_arg,
                b.pathFromRoot("extern/godot-cpp/gdextension/extension_api.json"),
                b.pathFromRoot("extern/godot-cpp"),
            },
        );

        var child = std.process.spawn(b.graph.io, .{
            .argv = &.{ python, "-c", gen_script },
        }) catch |err| {
            std.debug.print("Error running godot-cpp binding generator: {any}\n", .{err});
            return;
        };
        const term = child.wait(b.graph.io) catch |err| {
            std.debug.print("Error waiting on godot-cpp binding generator: {any}\n", .{err});
            return;
        };
        if (term.exited != 0) {
            std.debug.print("godot-cpp binding generator exited with code {d}\n", .{term.exited});
            return;
        }

        var stamp_file = b.build_root.handle.createFile(
            b.graph.io,
            gen_stamp_path,
            .{},
        ) catch |err| {
            std.debug.print("Warning: could not write gen stamp file: {any}\n", .{err});
            return;
        };
        defer stamp_file.close(b.graph.io);
        stamp_file.writeStreamingAll(b.graph.io, gen_stamp_contents) catch |err| {
            std.debug.print("Warning: could not write gen stamp file: {any}\n", .{err});
        };
    }

    const godot_lib = b.addLibrary(.{
        .name = "godot-cpp",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });
    targets.append(allocator, godot_lib) catch @panic("OOM");
    godot_lib.root_module.addIncludePath(b.path("extern/godot-cpp/include"));
    godot_lib.root_module.addIncludePath(b.path("extern/godot-cpp/gdextension"));
    godot_lib.root_module.addIncludePath(b.path("extern/godot-cpp/gen/include"));

    var godot_files: std.ArrayList([]const u8) = .empty;
    defer godot_files.deinit(allocator);

    const godot_src_dirs = &[_][]const u8{
        "extern/godot-cpp/src",
        "extern/godot-cpp/gen/src",
    };

    for (godot_src_dirs) |dir_path| {
        var dir = b.build_root.handle.openDir(
            b.graph.io,
            dir_path,
            .{ .iterate = true },
        ) catch continue;
        defer dir.close(b.graph.io);

        var walker = dir.walk(allocator) catch continue;
        defer walker.deinit();

        while (walker.next(b.graph.io) catch null) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.path, ".cpp")) {
                const full_path = b.pathJoin(&.{ dir_path, entry.path });
                godot_files.append(allocator, full_path) catch continue;
            }
        }
    }

    godot_lib.root_module.addCSourceFiles(.{
        .files = godot_files.items,
        .flags = cpp_flags,
    });

    const lib = b.addLibrary(.{
        .name = extension_name,
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
            .strip = optimize != .Debug,
        }),
    });
    targets.append(allocator, lib) catch @panic("OOM");
    lib.root_module.linkLibrary(godot_lib);
    lib.root_module.addIncludePath(b.path("extern/godot-cpp/include"));
    lib.root_module.addIncludePath(b.path("extern/godot-cpp/gdextension"));
    lib.root_module.addIncludePath(b.path("extern/godot-cpp/gen/include"));
    lib.root_module.addIncludePath(b.path("src"));

    var user_files: std.ArrayList([]const u8) = .empty;
    defer user_files.deinit(allocator);

    var src_dir = b.build_root.handle.openDir(
        b.graph.io,
        "src",
        .{ .iterate = true },
    ) catch |err| {
        std.debug.print("Error opening src directory: {}\n", .{err});
        return;
    };
    defer src_dir.close(b.graph.io);

    var src_walker = src_dir.walk(allocator) catch |err| {
        std.debug.print("Error walking src directory: {}\n", .{err});
        return;
    };
    defer src_walker.deinit();

    while (src_walker.next(b.graph.io) catch null) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.path, ".cpp")) {
            const full_path = b.pathJoin(&.{ "src", entry.path });
            user_files.append(allocator, full_path) catch continue;
        }
    }

    lib.root_module.addCSourceFiles(.{
        .files = user_files.items,
        .flags = cpp_flags,
    });

    const triple = target.result;
    const os_name = switch (triple.os.tag) {
        .windows => "windows",
        .linux => "linux",
        .macos => "macos",
        else => "unknown",
    };
    const arch_name = switch (triple.cpu.arch) {
        .x86_64 => "x86_64",
        .x86 => "x86_32",
        .aarch64 => "arm64",
        .riscv64 => "rv64",
        else => "unknown",
    };
    const build_type = switch (optimize) {
        .Debug => "template_debug",
        else => "template_release",
    };
    const prefix = switch (triple.os.tag) {
        .windows => "",
        else => "lib",
    };
    const ext = switch (triple.os.tag) {
        .windows => "dll",
        .macos => "dylib",
        else => "so",
    };

    const output_name = b.fmt(
        "{s}{s}.{s}.{s}.{s}.{s}",
        .{ prefix, extension_name, os_name, build_type, arch_name, ext },
    );

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .{ .custom = b.fmt("../project/bin/{s}", .{os_name}) } },
        .dest_sub_path = output_name,
        .pdb_dir = .{ .override = .{ .custom = b.fmt("../project/bin/{s}/godot_padding", .{os_name}) } },
    });
    b.getInstallStep().dependOn(&install.step);

    const cdb_step = zcc.createStep(b, "cdb", targets.toOwnedSlice(allocator) catch @panic("OOM"));
    b.getInstallStep().dependOn(cdb_step);
}
