const std = @import("std");
pub fn createModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const module = b.addModule("vulkan", .{
        .root_source_file = b.path("vulkan/src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vulkan_headers = b.dependency("vulkan_headers", .{});
    module.addIncludePath(vulkan_headers.path("include"));
    module.addIncludePath(b.path("src/windows"));
    module.linkSystemLibrary("vulkan", .{
        .needed = true,
        .preferred_link_mode = .static,
    });

    return module;
}

pub fn compileShaders(
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
