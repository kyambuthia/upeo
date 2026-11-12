const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_trans = b.addTranslateC(.{
        .root_source_file = b.path("src/engine/platform/c.h"),
        .target = target,
        .optimize = optimize,
    });

    if (b.graph.environ_map.get("HOME")) |home| {
        const local_inc = b.fmt("{s}/.local/include", .{home});
        c_trans.addIncludePath(.{ .cwd_relative = local_inc });
    }

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

    if (b.graph.environ_map.get("HOME")) |home| {
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
    run_cmd.addPassthruArgs();

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
