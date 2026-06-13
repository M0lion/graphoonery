const std = @import("std");

pub fn getModule(modules: anytype) *std.Build.Module {
    var b: *std.Build = modules.b;

    const module = b.createModule(.{
        .root_source_file = b.path("testbed/src/main.zig"),
        .target = modules.target,
        .optimize = modules.optimize,
        .imports = &.{
            modules.getImport("vulkan"),
            modules.getImport("window"),
            modules.getImport("ui"),
            modules.getImport("shaders"),
            modules.getImport("math"),
        },
    });

    return module;
}
pub fn createModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vulkanImport: std.Build.Module.Import,
    windowsImport: std.Build.Module.Import,
    uiImport: std.Build.Module.Import,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("testbed/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            vulkanImport,
            windowsImport,
            uiImport,
        },
    });

    return module;
}
