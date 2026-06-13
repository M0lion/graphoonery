const std = @import("std");

pub fn getModule(modules: anytype) *std.Build.Module {
    return createModule(modules.b, modules.target, modules.optimize);
}

pub fn createModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("math/src/index.zig"),
        .target = target,
        .optimize = optimize,
    });

    return module;
}
