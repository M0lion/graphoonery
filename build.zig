const std = @import("std");
const vulkan = @import("vulkan/build.zig");
const wayland = @import("wayland/build.zig");
const window = @import("window/build.zig");
const testbed = @import("testbed/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Generate shared artifacts once
    const shaders_module = vulkan.compileShaders(b, target, optimize) catch {
        @panic("Failed to compile shaders");
    };

    const vulkanImport = std.Build.Module.Import{
        .name = "vulkan",
        .module = vulkan.createModule(b, target, optimize),
    };
    const waylandImport = std.Build.Module.Import{
        .name = "wayland",
        .module = wayland.createModule(b, target, optimize),
    };
    const windowImport = std.Build.Module.Import{
        .name = "window",
        .module = window.createModule(b, target, optimize, vulkanImport),
    };

    const testbedModule = testbed.createModule(
        b,
        target,
        optimize,
        vulkanImport,
        windowImport,
    );
    addExe(b, testbedModule, "testbed");

    // Executable 1
    const mainModule = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            vulkanImport,
            waylandImport,
        },
    });
    const mainExe = b.addExecutable(.{
        .name = "graphoonery",
        .root_module = mainModule,
    });
    configureExecutable(b, mainExe, mainModule, target, shaders_module);
    b.installArtifact(mainExe);

    // Executable 2
    const lockscreenModule = b.createModule(.{
        .root_source_file = b.path("src/lockscreen.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            vulkanImport,
            waylandImport,
        },
    });
    const lockscreenExe = b.addExecutable(.{
        .name = "lockfoonery",
        .root_module = lockscreenModule,
    });
    lockscreenExe.linkSystemLibrary("pam");
    configureExecutable(b, lockscreenExe, lockscreenModule, target, shaders_module);
    b.installArtifact(lockscreenExe);

    // Run step
    const run_cmd = b.addRunArtifact(mainExe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Lock step
    const lockCmd = b.addRunArtifact(lockscreenExe);
    lockCmd.step.dependOn(b.getInstallStep());
    const lockStep = b.step("lock", "Run the lockscreen");
    lockStep.dependOn(&lockCmd.step);
}

fn addExe(
    b: *std.Build,
    module: *std.Build.Module,
    name: []const u8,
) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = module,
    });
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step(name, b.fmt("Run {s}", .{name}));
    run_step.dependOn(&run_cmd.step);
}

fn configureExecutable(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    shaders_module: *std.Build.Module,
) void {
    // Add shaders module
    module.addImport("shaders", shaders_module);

    // Platform-specific setup
    if (target.result.os.tag == .macos) {
        exe.addCSourceFile(.{
            .file = b.path("src/macos_window.m"),
        });
        exe.linkFramework("Cocoa");
        exe.linkFramework("QuartzCore");
        exe.linkFramework("Metal");
        exe.linkSystemLibrary("MoltenVK");
    } else {}

    exe.linkLibC();
}
