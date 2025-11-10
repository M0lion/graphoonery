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
        generateWaylandProtocols(b, exe);

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

fn generateWaylandProtocols(b: *std.Build, exe: *std.Build.Step.Compile) void {
    generateWaylandProtocol(
        b,
        exe,
        "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml",
    );
    generateWaylandProtocol(
        b,
        exe,
        "/usr/share/wayland-protocols/staging/ext-session-lock/ext-session-lock-v1.xml",
    );
}

fn generateWaylandProtocol(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    comptime path: []const u8,
) void {
    // Run wayland-scanner to generate C protocol files
    const wayland_scanner = b.addSystemCommand(&.{ "wayland-scanner", "client-header" });
    wayland_scanner.addArg(path);
    const name = comptime std.fs.path.stem(path);
    const headerFileName = std.fmt.comptimePrint("{s}-client-protocol.h", .{name});
    const header_file = wayland_scanner.addOutputFileArg(headerFileName);

    const wayland_scanner_code = b.addSystemCommand(&.{ "wayland-scanner", "private-code" });
    wayland_scanner_code.addArg(path);
    const codeFileName = std.fmt.comptimePrint("{s}-client-protocol.c", .{name});
    const code_file = wayland_scanner_code.addOutputFileArg(codeFileName);

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
