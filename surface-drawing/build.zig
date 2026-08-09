const std = @import("std");

pub const Dependencies = struct {
    vulkan: std.Build.Module.Import,
    windows: std.Build.Module.Import,
};

pub fn createModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vulkanImport: std.Build.Module.Import,
    windowsImport: std.Build.Module.Import,
    mathImport: std.Build.Module.Import,
    uiImport: std.Build.Module.Import,
    shadersImport: std.Build.Module.Import,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("surface-drawing/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            vulkanImport,
            windowsImport,
            mathImport,
            uiImport,
            shadersImport,
        },
    });

    return module;
}
