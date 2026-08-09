const std = @import("std");

pub const Dependencies = struct {};

pub fn createModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    _: anytype,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("ui/src/ui.zig"),
        .target = target,
        .optimize = optimize,
    });

    return module;
}
