const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const opt_wasmer_dir_desc = "Wasmer release location. Falls back to WASMER_DIR env var if not set";
    const opt_wasmer_dir = b.option([]const u8, "wasmer-dir", opt_wasmer_dir_desc);

    const build_examples_option = b.option(bool, "examples", "Build example files") orelse false;

    const run_step = b.step("run", "Run the app");

    const wasmer_module = b.addModule("wasmer", .{
        .root_source_file = b.path("src/wasmer.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (build_examples_option) {
        var examples_dir = b.build_root.handle.openDir(b.graph.io, "examples", .{ .iterate = true }) catch
            @panic("failed to open examples directory");
        defer examples_dir.close(b.graph.io);

        var examples_dir_iter = examples_dir.iterate();

        while (examples_dir_iter.next(b.graph.io) catch @panic("failed to iterate examples")) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
                const exe_name = entry.name[0 .. entry.name.len - 4];
                const exe_path = std.fmt.allocPrint(b.allocator, "examples/{s}", .{entry.name}) catch @panic("OOM");

                const example_exe = b.addExecutable(.{
                    .name = exe_name,
                    .root_module = b.createModule(.{
                        .root_source_file = b.path(exe_path),
                        .target = target,
                        .optimize = optimize,
                        .link_libc = true,
                    }),
                });

                const lib_path = wasmerLibPath(b, opt_wasmer_dir, &example_exe.step);
                example_exe.root_module.addImport("wasmer", wasmer_module);
                example_exe.root_module.addLibraryPath(.{ .cwd_relative = lib_path });
                example_exe.root_module.linkSystemLibrary("wasmer", .{});

                b.installArtifact(example_exe);
                const run_example_cmd = b.addRunArtifact(example_exe);
                run_example_cmd.step.dependOn(b.getInstallStep());

                run_step.dependOn(&run_example_cmd.step);
            }
        }
    }

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const wasmer_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasmer.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const lib_path = wasmerLibPath(b, opt_wasmer_dir, &wasmer_unit_tests.step);
    wasmer_unit_tests.root_module.addLibraryPath(.{ .cwd_relative = lib_path });
    wasmer_unit_tests.root_module.linkSystemLibrary("wasmer", .{});

    const run_wasmer_unit_tests = b.addRunArtifact(wasmer_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_wasmer_unit_tests.step);

    // Build docs
    const docs_step = b.step("docs", "Emit docs");
    const docs_obj = b.addObject(.{
        .name = "wasmer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasmer.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const docs = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&docs.step);
}

/// Attempt to resolve the Wasmer `lib` path, inserting a fail step if the base path is unknown
fn wasmerLibPath(b: *std.Build, path: ?[]const u8, step: *std.Build.Step) []const u8 {
    const dir = path orelse b.graph.environ_map.get("WASMER_DIR");

    const fail_message = "Wasmer location not set. Use wasmer-dir or set WASMER_DIR in env";
    if (dir == null) step.dependOn(&b.addFail(fail_message).step);

    return if (dir) |d| b.pathJoin(&.{ d, "lib" }) else "";
}
