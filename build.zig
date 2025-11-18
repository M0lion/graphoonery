const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Generate shared artifacts once
    const shaders_module = compileShaders(b, target, optimize) catch {
        @panic("Failed to compile shaders");
    };
    const wayland_protocols = if (target.result.os.tag != .macos)
        generateWaylandProtocols(b)
    else
        null;

    // Executable 1
    const mainModule = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mainExe = b.addExecutable(.{
        .name = "graphoonery",
        .root_module = mainModule,
    });
    configureExecutable(b, mainExe, mainModule, target, shaders_module, wayland_protocols);
    b.installArtifact(mainExe);

    // Executable 2
    const lockscreenModule = b.createModule(.{
        .root_source_file = b.path("src/lockscreen.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lockscreenExe = b.addExecutable(.{
        .name = "lockfoonery",
        .root_module = lockscreenModule,
    });
    configureExecutable(b, lockscreenExe, lockscreenModule, target, shaders_module, wayland_protocols);
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

const WaylandProtocols = struct {
    xdg_shell_code: std.Build.LazyPath,
    xdg_shell_header_dir: std.Build.LazyPath,
    session_lock_code: std.Build.LazyPath,
    session_lock_header_dir: std.Build.LazyPath,
};

fn configureExecutable(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    shaders_module: *std.Build.Module,
    wayland_protocols: ?WaylandProtocols,
) void {
    // Add shaders module
    module.addImport("shaders", shaders_module);

    // Add Vulkan headers
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    exe.addIncludePath(vulkan_headers.path("include"));
    exe.addIncludePath(b.path("src/windows"));

    // Platform-specific setup
    if (target.result.os.tag == .macos) {
        exe.addCSourceFile(.{
            .file = b.path("src/macos_window.m"),
        });
        exe.linkFramework("Cocoa");
        exe.linkFramework("QuartzCore");
        exe.linkFramework("Metal");
        exe.linkSystemLibrary("MoltenVK");
    } else {
        // Add pre-generated Wayland protocols
        if (wayland_protocols) |protocols| {
            exe.addCSourceFile(.{ .file = protocols.xdg_shell_code });
            exe.addIncludePath(protocols.xdg_shell_header_dir);
            exe.addCSourceFile(.{ .file = protocols.session_lock_code });
            exe.addIncludePath(protocols.session_lock_header_dir);
        }
        exe.linkSystemLibrary("wayland-client");
        exe.linkSystemLibrary("wayland-egl");
        exe.linkSystemLibrary("vulkan");
        exe.linkSystemLibrary("xkbcommon");
        exe.linkSystemLibrary("pam");
    }

    exe.linkLibC();
}

fn generateWaylandProtocols(b: *std.Build) WaylandProtocols {
    const xdg = generateWaylandProtocol(
        b,
        "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml",
    );
    const session_lock = generateWaylandProtocol(
        b,
        "/usr/share/wayland-protocols/staging/ext-session-lock/ext-session-lock-v1.xml",
    );

    return .{
        .xdg_shell_code = xdg.code,
        .xdg_shell_header_dir = xdg.header_dir,
        .session_lock_code = session_lock.code,
        .session_lock_header_dir = session_lock.header_dir,
    };
}

fn generateWaylandProtocol(
    b: *std.Build,
    comptime path: []const u8,
) struct { code: std.Build.LazyPath, header_dir: std.Build.LazyPath } {
    const wayland_scanner = b.addSystemCommand(&.{ "wayland-scanner", "client-header" });
    wayland_scanner.addArg(path);
    const name = comptime std.fs.path.stem(path);
    const headerFileName = std.fmt.comptimePrint("{s}-client-protocol.h", .{name});
    const header_file = wayland_scanner.addOutputFileArg(headerFileName);

    const wayland_scanner_code = b.addSystemCommand(&.{ "wayland-scanner", "private-code" });
    wayland_scanner_code.addArg(path);
    const codeFileName = std.fmt.comptimePrint("{s}-client-protocol.c", .{name});
    const code_file = wayland_scanner_code.addOutputFileArg(codeFileName);

    return .{
        .code = code_file,
        .header_dir = header_file.dirname(),
    };
}

fn compileShaders(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !*std.Build.Module {
    const shaders = [_]struct { path: []const u8, name: []const u8 }{
        .{ .path = "shaders/vertex.vert", .name = "vertex_vert_spv" },
        .{ .path = "shaders/fragment.frag", .name = "fragment_frag_spv" },
    };

    const wf = b.addWriteFiles();
    var shader_zig_contents = try std.ArrayList(u8).initCapacity(b.allocator, 0);
    const writer = shader_zig_contents.writer(b.allocator);

    for (shaders) |shader| {
        const glslc = b.addSystemCommand(&[_][]const u8{"glslc"});
        glslc.addFileArg(b.path(shader.path));
        glslc.addArg("-o");
        const output = glslc.addOutputFileArg(b.fmt("{s}.spv", .{shader.name}));
        _ = wf.addCopyFile(output, b.fmt("{s}.spv", .{shader.name}));
        writer.print("pub const {s} = @embedFile(\"{s}.spv\");\n", .{ shader.name, shader.name }) catch @panic("OOM");
    }

    const shaders_zig = wf.add("shaders.zig", shader_zig_contents.items);
    return b.addModule("shaders", .{
        .root_source_file = shaders_zig,
        .target = target,
        .optimize = optimize,
    });
}
