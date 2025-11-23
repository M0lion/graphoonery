const std = @import("std");

pub fn createModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vulkanImport: std.Build.Module.Import,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("window/src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            vulkanImport,
        },
    });

    module.addIncludePath(b.path("window/glfw/include/"));
    module.addObjectFile(b.path(getGLFWLibPath(target)));
    module.link_libc = true;

    return module;
}

fn getGLFWLibPath(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.os.tag) {
        .windows => switch (target.result.cpu.arch) {
            .x86_64 => "window/glfw/windows/glfw3.lib",
            else => @panic("Unsupported Windows architecture"),
        },
        .linux => switch (target.result.cpu.arch) {
            .x86_64 => "window/glfw/linux/libglfw3.a",
            else => @panic("Unsupported Linux architecture"),
        },
        .macos => switch (target.result.cpu.arch) {
            .aarch64 => "window/glfw/macos/arm/libglfw3.a",
            .x86_64 => "window/glfw/macos/x86_64/libglfw3.a",
            else => @panic("Unsupported macOS architecture"),
        },
        else => @panic("Unsupported platform"),
    };
}
