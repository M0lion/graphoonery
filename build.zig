const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "macos-window",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add Vulkan headers from dependency
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    exe.addIncludePath(vulkan_headers.path("include"));

    // Add Objective-C file
    exe.addCSourceFile(.{
        .file = b.path("src/macos_window.m"),
    });

    // Link frameworks and libraries
    if (target.result.os.tag == .macos) {
        exe.linkFramework("Cocoa");
        exe.linkFramework("QuartzCore");
        exe.linkFramework("Metal");
        exe.linkSystemLibrary("MoltenVK");
    } else {
        exe.linkSystemLibrary("vulkan");
    }
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
