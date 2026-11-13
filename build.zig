const std = @import("std");

/// Reads an environment variable in a way that works on both the Zig 0.16
/// (`env_map`) and 0.17 (`environ_map`) build graph layouts.
fn getEnv(b: *std.Build, name: []const u8) ?[]const u8 {
    if (comptime @hasField(@TypeOf(b.graph.*), "environ_map")) {
        return b.graph.environ_map.get(name);
    } else if (comptime @hasField(@TypeOf(b.graph.*), "env_map")) {
        return b.graph.env_map.get(name);
    }
    return null;
}

/// Adds C include paths from `~/.local/include` and from Nix's
/// `NIX_CFLAGS_COMPILE` so headers resolve in both environments.
fn addHostIncludePaths(b: *std.Build, step: *std.Build.Step.TranslateC) void {
    if (getEnv(b, "HOME")) |home| {
        step.addIncludePath(.{ .cwd_relative = b.fmt("{s}/.local/include", .{home}) });
    }
    if (getEnv(b, "NIX_CFLAGS_COMPILE")) |cflags| {
        var it = std.mem.tokenizeScalar(u8, cflags, ' ');
        while (it.next()) |tok| {
            if (std.mem.eql(u8, tok, "-isystem") or std.mem.eql(u8, tok, "-I")) {
                if (it.next()) |inc| step.addIncludePath(.{ .cwd_relative = inc });
            }
        }
    }
}

/// Links the platform libraries the engine needs into `mod`.
fn linkPlatform(b: *std.Build, mod: *std.Build.Module) void {
    if (getEnv(b, "HOME")) |home| {
        mod.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/.local/lib", .{home}) });
    }
    mod.link_libc = true;
    mod.linkSystemLibrary("SDL3", .{});
}

fn addPassthruArgs(b: *std.Build, run: *std.Build.Step.Run) void {
    if (comptime @hasDecl(@TypeOf(run.*), "addPassthruArgs")) {
        run.addPassthruArgs();
    } else if (b.args) |args| {
        run.addArgs(args);
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // C bindings (SDL3 + GLES3 headers) translated into a Zig module.
    const c_trans = b.addTranslateC(.{
        .root_source_file = b.path("src/engine/platform/c.h"),
        .target = target,
        .optimize = optimize,
    });
    addHostIncludePaths(b, c_trans);
    c_trans.link_libc = true;
    const c_mod = c_trans.createModule();

    // The engine as a reusable module: `@import("upeo")`.
    const upeo = b.addModule("upeo", .{
        .root_source_file = b.path("src/upeo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "c", .module = c_mod }},
    });
    upeo.link_libc = true;

    // Example: marble demo.
    const marble_mod = b.createModule(.{
        .root_source_file = b.path("examples/marble/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "upeo", .module = upeo }},
    });
    linkPlatform(b, marble_mod);
    const marble = b.addExecutable(.{ .name = "upeo-marble", .root_module = marble_mod });
    b.installArtifact(marble);

    const run_marble = b.addRunArtifact(marble);
    run_marble.step.dependOn(b.getInstallStep());
    addPassthruArgs(b, run_marble);
    b.step("run", "Run the marble demo").dependOn(&run_marble.step);

    // Tests: engine + examples. Both link SDL so tests may touch platform code.
    const test_step = b.step("test", "Run engine and example unit tests");

    const engine_test_mod = b.createModule(.{
        .root_source_file = b.path("src/upeo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "c", .module = c_mod }},
    });
    linkPlatform(b, engine_test_mod);
    const engine_tests = b.addTest(.{ .name = "engine-tests", .root_module = engine_test_mod });
    test_step.dependOn(&b.addRunArtifact(engine_tests).step);

    const marble_tests = b.addTest(.{ .name = "marble-tests", .root_module = marble_mod });
    test_step.dependOn(&b.addRunArtifact(marble_tests).step);

    // WebAssembly (Emscripten / WebGL 2.0) build step: `zig build wasm`
    const emsdk_sysroot = getEnv(b, "EMSDK_SYSROOT") orelse "/usr/local/emsdk/upstream/emscripten/cache/sysroot";
    const emcc_bin = getEnv(b, "EMCC") orelse "/usr/local/emsdk/upstream/emscripten/emcc";
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .emscripten,
    });
    const wasm_c_trans = b.addTranslateC(.{
        .root_source_file = b.path("src/engine/platform/c.h"),
        .target = wasm_target,
        .optimize = optimize,
    });
    wasm_c_trans.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{emsdk_sysroot}) });
    wasm_c_trans.link_libc = true;
    const wasm_c_mod = wasm_c_trans.createModule();

    const wasm_upeo = b.addModule("upeo-wasm", .{
        .root_source_file = b.path("src/upeo.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "c", .module = wasm_c_mod }},
    });
    wasm_upeo.link_libc = true;

    const wasm_marble_mod = b.createModule(.{
        .root_source_file = b.path("examples/marble/main.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "upeo", .module = wasm_upeo }},
    });
    wasm_marble_mod.link_libc = true;

    const wasm_lib = b.addLibrary(.{
        .name = "upeo-marble",
        .linkage = .static,
        .root_module = wasm_marble_mod,
    });

    const wasm_mkdir = b.addSystemCommand(&.{ "mkdir", "-p", "zig-out/web" });
    const emcc_cmd = b.addSystemCommand(&.{
        emcc_bin,
        "-sUSE_SDL=3",
        "-sMIN_WEBGL_VERSION=2",
        "-sMAX_WEBGL_VERSION=2",
        "-sFULL_ES3=1",
        "-sALLOW_MEMORY_GROWTH=1",
        "-o",
        "zig-out/web/index.html",
    });
    emcc_cmd.addArtifactArg(wasm_lib);
    emcc_cmd.step.dependOn(&wasm_mkdir.step);
    b.step("wasm", "Build WebAssembly (Emscripten + WebGL 2.0) bundle").dependOn(&emcc_cmd.step);
}
