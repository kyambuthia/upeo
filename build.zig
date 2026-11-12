const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_trans = b.addTranslateC(.{
        .root_source_file = b.path("src/engine/platform/c.h"),
        .target = target,
        .optimize = optimize,
    });

    const local_home = if (comptime @hasField(@TypeOf(b.graph.*), "environ_map"))
        b.graph.environ_map.get("HOME")
    else if (comptime @hasField(@TypeOf(b.graph.*), "env_map"))
        b.graph.env_map.get("HOME")
    else
        null;

    if (local_home) |home| {
        const local_inc = b.fmt("{s}/.local/include", .{home});
        c_trans.addIncludePath(.{ .cwd_relative = local_inc });
    }

    c_trans.link_libc = true;
    c_trans.linkSystemLibrary("SDL3", .{});
    c_trans.linkSystemLibrary("GLESv2", .{});

    const c_mod = c_trans.createModule();

    const exe = b.addExecutable(.{
        .name = "upeo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c", .module = c_mod },
            },
        }),
    });

    if (local_home) |home| {
        const local_lib = b.fmt("{s}/.local/lib", .{home});
        exe.root_module.addLibraryPath(.{ .cwd_relative = local_lib });
        const local_inc = b.fmt("{s}/.local/include", .{home});
        exe.root_module.addIncludePath(.{ .cwd_relative = local_inc });
    }

    exe.root_module.link_libc = true;
    exe.root_module.linkSystemLibrary("SDL3", .{});
    exe.root_module.linkSystemLibrary("GLESv2", .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (comptime @hasDecl(@TypeOf(run_cmd.*), "addPassthruArgs")) {
        run_cmd.addPassthruArgs();
    } else {
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    }

    const run_step = b.step("run", "Run Upeo 3D");
    run_step.dependOn(&run_cmd.step);

    // Unit test step
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run engine unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
