const std = @import("std");
const builtin = @import("builtin");
pub const wasm = @import("./wasm.zig");

pub const wasi = @import("./wasi.zig");
pub const WasiError = wasi.WasiError;
pub const WasiConfig = wasi.WasiConfig;
pub const WasiEnv = wasi.WasiEnv;
pub const WasiVersion = wasi.WasiVersion;
pub const getWasiVersion = wasi.getWasiVersion;
pub const getImports = wasi.getImports;
pub const getStartFunction = wasi.getStartFunction;

// Re-exports
pub const ExternVec = wasm.ExternVec;
pub const ByteVec = wasm.ByteVec;
pub const Engine = wasm.Engine;
pub const Store = wasm.Store;
pub const Module = wasm.Module;
pub const Instance = wasm.Instance;
pub const Extern = wasm.Extern;
pub const Func = wasm.Func;
pub const Memory = wasm.Memory;
pub const MemoryType = wasm.MemoryType;
pub const Limits = wasm.Limits;

const OS_PATH_MAX: usize = switch (builtin.os.tag) {
    .windows => std.os.windows.MAX_PATH,
    .linux, .macos => std.os.linux.PATH_MAX,
    else => std.math.maxInt(usize),
};

/// Detect Wasmer library directory
pub fn detectWasmerLibDir(allocator: std.mem.Allocator) !?[]const u8 {
    const argv = [_][]const u8{ "wasmer", "config", "--libdir" };

    // By default, child will inherit stdout & stderr from its parents,
    // this usually means that child's output will be printed to terminal.
    // Here we change them to pipe and collect into `ArrayList`.
    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    var stdout = std.ArrayListUnmanaged(u8){};
    var stderr = std.ArrayListUnmanaged(u8){};
    defer {
        stdout.deinit(allocator);
        stderr.deinit(allocator);
    }

    try child.spawn();
    try child.collectOutput(allocator, &stdout, &stderr, OS_PATH_MAX);

    const term = try child.wait();

    if (stderr.items.len != 0 or term.Exited != 0) return null;

    const stdout_res = try stdout.toOwnedSlice(allocator);
    defer allocator.free(stdout_res);

    return try allocator.dupe(u8, std.mem.trimRight(u8, stdout_res, "\r\n"));
}

pub fn setupTracing(verbosity_level: usize, use_colors: usize) void {
    wasmer_setup_tracing(@as(c_int, @intCast(verbosity_level)), @as(c_int, @intCast(use_colors)));
}

pub extern "c" fn wasmer_setup_tracing(c_int, c_int) void;

pub fn lastError(allocator: std.mem.Allocator) ![:0]u8 {
    const buf_len = @as(usize, @intCast(wasmer_last_error_length()));
    const buf = try allocator.alloc(u8, buf_len);
    _ = wasmer_last_error_message(buf.ptr, @as(c_int, @intCast(buf_len)));
    return buf[0 .. buf_len - 1 :0];
}

pub extern "c" fn wasmer_last_error_length() c_int;
pub extern "c" fn wasmer_last_error_message([*]const u8, c_int) c_int;

pub fn watToWasm(wat: []const u8) !ByteVec {
    var wat_bytes = ByteVec.fromSlice(wat);
    defer wat_bytes.deinit();

    var wasm_bytes: ByteVec = undefined;
    wat2wasm(&wat_bytes, &wasm_bytes);

    if (wasm_bytes.size == 0) return error.WatParse;

    return wasm_bytes;
}

extern "c" fn wat2wasm(*const wasm.ByteVec, *wasm.ByteVec) void;

test "detect wasmer lib directory" {
    const result = try detectWasmerLibDir(std.testing.allocator) orelse "";
    defer std.testing.allocator.free(result);

    try std.testing.expectStringEndsWith(result, ".wasmer/lib");
}

test "transform WAT to WASM" {
    const wat =
        \\(module
        \\  (type $add_one_t (func (param i32) (result i32)))
        \\  (func $add_one_f (type $add_one_t) (param $value i32) (result i32)
        \\    local.get $value
        \\    i32.const 1
        \\    i32.add)
        \\  (export "add_one" (func $add_one_f)))
    ;

    var wasm_bytes = try watToWasm(wat);

    try std.testing.expectEqual(91, wasm_bytes.size);

    defer wasm_bytes.deinit();
}
