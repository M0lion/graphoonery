const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan/vk.zig");
const c = vk.c;
const windows = @import("windows/window.zig");
const VulkanContext = @import("vulkan/vulkanContext.zig").VulkanContext;
const sc = @import("vulkan/swapchain.zig");
const pipeline = @import("vulkan/pipeline.zig");
const command = @import("vulkan/command.zig");
const sync = @import("vulkan/sync.zig");
const buffer = @import("vulkan/buffer.zig");
const descriptor = @import("vulkan/descriptor.zig");
const wayland_c = if (builtin.os.tag != .macos) @import("windows/wayland/wayland_c.zig") else struct {
    const c = struct {};
};
const math = @import("math/index.zig");
const shaders = @import("shaders");
const vertShaderCode = shaders.vertex_vert_spv;
const fragShaderCode = shaders.fragment_frag_spv;
const ColoredVertexPipeline = @import("coloredVertexPipeline.zig").ColoredVertexPipeline;
const cube = @import("cube.zig");
const dodec = @import("dodecahedron.zig");
const pam = @import("pam.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    var password = [_]u8{ 'f', 'o', 'o', 'b', 'a', 'r', 0 };
    _ = pam.authenticate(allocator, password[0..]);

    std.log.debug("Window init", .{});
    var window = try windows.Window.init(allocator);
    try window.finishInit();
    std.log.debug("Window: {*}", .{&window});
    defer window.deinit();

    std.log.debug("Vulkan init", .{});
    var vulkanContext = try VulkanContext.init(&window, allocator);
    defer vulkanContext.deinit();

    const logicalDevice = vulkanContext.logicalDevice;
    std.log.debug("Loading shaders", .{});

    var coloredVertexPipeline = try ColoredVertexPipeline.init(vulkanContext);
    defer coloredVertexPipeline.deinit();

    const mesh = try cube.getCube(&coloredVertexPipeline);
    defer mesh.deinit();
    const dodecahedron = try dodec.getDodecahedron(allocator, &coloredVertexPipeline);
    defer dodecahedron.deinit();

    var transform = try ColoredVertexPipeline.TransformUBO.init(&coloredVertexPipeline);
    defer transform.deinit() catch |err| {
        std.log.err("Failed to free transform: {}", .{err});
    };
    var dodecTransform = try ColoredVertexPipeline.TransformUBO.init(&coloredVertexPipeline);
    defer dodecTransform.deinit() catch |err| {
        std.log.err("Failed to free dodecTransform: {}", .{err});
    };

    // Flush all Wayland requests before rendering
    if (builtin.os.tag != .macos) {
        if (window.windowHandle.display) |display| {
            _ = wayland_c.c.wl_display_flush(display);
        }
    }

    var width, var height = window.getWindowSize();
    var aspect =
        @as(f32, @floatFromInt(width)) /
        @as(f32, @floatFromInt(height));

    var t = math.Mat4.identity();
    var p = math.Mat4.createPerspective(90, aspect, 0.01, 10);
    var dt = math.Mat4.identity();
    try transform.update(&t, &p);
    try dodecTransform.update(&dt, &p);

    // Event loop
    var time: f32 = 0.0;
    while (window.pollEvents()) {
        width, height = window.getWindowSize();
        t = math.Mat4.createRotation(time * 10, time * 6, time * 30);
        t = math.Mat4.createTranslation(0, 0, -5).multiply(&t);
        t = math.Mat4.createTranslation(-1, 1.5, 0).multiply(&t);
        dt = math.Mat4.createRotation(time * 6, time * 30, time * 10);
        dt = math.Mat4.createTranslation(0, 0, -5).multiply(&dt);
        dt = math.Mat4.createTranslation(1, -1.5, 0).multiply(&dt);
        if (vulkanContext.width != width or vulkanContext.height != height) {
            try vulkanContext.resize();
            aspect =
                @as(f32, @floatFromInt(width)) /
                @as(f32, @floatFromInt(height));
            p = math.Mat4.createPerspective(90, aspect, 0.01, 10);
            try transform.update(&t, &p);
            try dodecTransform.update(&dt, &p);
        } else {
            try transform.update(&t, null);
            try dodecTransform.update(&dt, null);
        }

        {
            const commandBuffer = try vulkanContext.beginDraw();
            defer vulkanContext.endDraw() catch {
                @panic("Failed to end draw");
            };
            try coloredVertexPipeline.draw(commandBuffer, &transform, &mesh);
            try coloredVertexPipeline.draw(commandBuffer, &dodecTransform, &dodecahedron);
        }

        time += 0.001;
        std.Thread.sleep(10 * std.time.ns_per_ms); // Sleep 100ms between frames
    }
    try vk.checkResult(c.vkDeviceWaitIdle(logicalDevice));
}
