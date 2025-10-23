const std = @import("std");
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "macos-window",
        .root_module = module,
    });

    // Add Vulkan headers from dependency
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    exe.addIncludePath(vulkan_headers.path("include"));

    // Link frameworks and libraries
    if (target.result.os.tag == .macos) {
        // Add Objective-C file
        exe.addCSourceFile(.{
            .file = b.path("src/macos_window.m"),
        });

        exe.linkFramework("Cocoa");
        exe.linkFramework("QuartzCore");
        exe.linkFramework("Metal");
        exe.linkSystemLibrary("MoltenVK");
    } else {
        module.addImport("wayland", getWayland(b));
        exe.linkSystemLibrary("wayland-client");
        exe.linkSystemLibrary("wayland-egl");
        exe.linkSystemLibrary("vulkan");
    }
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn getWayland(b: *std.Build) *std.Build.Module {
    const scanner = Scanner.create(b, .{});

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addCustomProtocol(b.path("protocols/wlr-layer-shell-v1.xml"));

    // Pass the maximum version implemented by your wayland server or client.
    // Requests, events, enums, etc. from newer versions will not be generated,
    // ensuring forwards compatibility with newer protocol xml.
    // This will also generate code for interfaces created using the provided
    // global interface, in this example wl_keyboard, wl_pointer, xdg_surface,
    // xdg_toplevel, etc. would be generated as well.
    scanner.generate("wl_compositor", 6);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 4);
    scanner.generate("xdg_wm_base", 3);
    scanner.generate("zwlr_layer_shell_v1", 5);

    return wayland;
}
