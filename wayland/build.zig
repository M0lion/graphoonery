const std = @import("std");

pub fn createModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("wayland/src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const protocols = generateWaylandProtocols(b);

    module.addCSourceFile(.{ .file = protocols.xdg_shell_code });
    module.addIncludePath(protocols.xdg_shell_header_dir);
    module.addCSourceFile(.{ .file = protocols.session_lock_code });
    module.addIncludePath(protocols.session_lock_header_dir);
    module.linkSystemLibrary("wayland-client", .{
        .needed = true,
        .preferred_link_mode = .static,
    });
    module.linkSystemLibrary("xkbcommon", .{
        .needed = true,
        .preferred_link_mode = .static,
    });
    //module.linkSystemLibrary("wayland-egl", .{
    //    .needed = true,
    //    .preferred_link_mode = .static,
    //});

    return module;
}

const WaylandProtocols = struct {
    xdg_shell_code: std.Build.LazyPath,
    xdg_shell_header_dir: std.Build.LazyPath,
    session_lock_code: std.Build.LazyPath,
    session_lock_header_dir: std.Build.LazyPath,
};

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
