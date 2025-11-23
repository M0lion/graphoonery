const std = @import("std");

pub fn createModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vulkanImport: std.Build.Module.Import,
    windowsImport: std.Build.Module.Import,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("testbed/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            vulkanImport,
            windowsImport,
        },
    });

    return module;
}
