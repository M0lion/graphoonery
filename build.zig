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

    compileShaders(b, module) catch {
        @panic("Failed to compile shaders");
    };

    const exe = b.addExecutable(.{
        .name = "macos-window",
        .root_module = module,
    });

    // Add Vulkan headers from dependency
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    exe.addIncludePath(vulkan_headers.path("include"));

    exe.addIncludePath(b.path("src/windows"));
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
        // Generate xdg-shell protocol C headers
        generateWaylandProtocol(b, exe);

        module.addImport("wayland", getWayland(b));
        exe.linkSystemLibrary("wayland-client");
        exe.linkSystemLibrary("wayland-egl");
        exe.linkSystemLibrary("vulkan");
        exe.linkSystemLibrary("xkbcommon");
        exe.linkSystemLibrary("pam");
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

fn generateWaylandProtocol(b: *std.Build, exe: *std.Build.Step.Compile) void {
    // Run wayland-scanner to generate C protocol files
    const wayland_scanner = b.addSystemCommand(&.{ "wayland-scanner", "client-header" });
    wayland_scanner.addArg("/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml");
    const header_file = wayland_scanner.addOutputFileArg("xdg-shell-client-protocol.h");

    const wayland_scanner_code = b.addSystemCommand(&.{ "wayland-scanner", "private-code" });
    wayland_scanner_code.addArg("/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml");
    const code_file = wayland_scanner_code.addOutputFileArg("xdg-shell-client-protocol.c");

    // Add generated files to the executable
    exe.addCSourceFile(.{
        .file = code_file,
    });
    exe.addIncludePath(header_file.dirname());
}

fn compileShaders(b: *std.Build, module: *std.Build.Module) !void {
    const shaders = [_]struct { path: []const u8, name: []const u8 }{
        .{ .path = "shaders/vertex.vert", .name = "vertex_vert_spv" },
        .{ .path = "shaders/fragment.frag", .name = "fragment_frag_spv" },
    };

    // Create a WriteFiles step to generate our wrapper
    const wf = b.addWriteFiles();

    var shader_zig_contents = try std.ArrayList(u8).initCapacity(b.allocator, 0);
    const writer = shader_zig_contents.writer(b.allocator);

    for (shaders) |shader| {
        const glslc = b.addSystemCommand(&[_][]const u8{"glslc"});
        glslc.addFileArg(b.path(shader.path));
        glslc.addArg("-o");
        const output = glslc.addOutputFileArg(b.fmt("{s}.spv", .{shader.name}));

        // Copy the spv file into our write files directory
        _ = wf.addCopyFile(output, b.fmt("{s}.spv", .{shader.name}));

        // Generate: pub const vertex_vert_spv = @embedFile("vertex_vert_spv.spv");
        writer.print("pub const {s} = @embedFile(\"{s}.spv\");\n", .{ shader.name, shader.name }) catch @panic("OOM");
    }

    // Write the generated Zig file
    const shaders_zig = wf.add("shaders.zig", shader_zig_contents.items);

    // Add as a module
    const shaders_module = b.addModule("shaders", .{
        .root_source_file = shaders_zig,
    });

    module.addImport("shaders", shaders_module);
}
