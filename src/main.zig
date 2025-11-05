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
const wayland_c = if (builtin.os.tag != .macos) @import("windows/wayland_c.zig") else struct {
    const c = struct {};
};
const math = @import("math/index.zig");
const shaders = @import("shaders");
const vertShaderCode = shaders.vertex_vert_spv;
const fragShaderCode = shaders.fragment_frag_spv;
const ColoredVertexPipeline = @import("coloredVertexPipeline.zig").ColoredVertexPipeline;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

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

    var transform = try ColoredVertexPipeline.TransformUBO.init(&coloredVertexPipeline);
    defer transform.deinit() catch |err| {
        std.log.err("Failed to free transform: {}", .{err});
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
    try transform.update(&t, &p);

    // Event loop
    var time: f32 = 0.0;
    while (window.pollEvents()) {
        width, height = window.getWindowSize();
        t = math.Mat4.createRotation(time * 10, time * 6, time * 3);
        t = math.Mat4.createTranslation(0, 0, -5).multiply(&t);
        if (vulkanContext.width != width or vulkanContext.height != height) {
            try vulkanContext.resize();
            aspect =
                @as(f32, @floatFromInt(width)) /
                @as(f32, @floatFromInt(height));
            p = math.Mat4.createPerspective(90, aspect, 0.01, 10);
            try transform.update(&t, &p);
        } else {
            try transform.update(&t, null);
        }

        try render(
            &vulkanContext,
            &coloredVertexPipeline,
            &transform,
        );
        time += 0.001;
        std.Thread.sleep(10 * std.time.ns_per_ms); // Sleep 100ms between frames
    }
    try vk.checkResult(c.vkDeviceWaitIdle(logicalDevice));
}

fn render(
    context: *VulkanContext,
    coloredVertexPipeline: *ColoredVertexPipeline,
    trans: *ColoredVertexPipeline.TransformUBO,
) !void {
    {
        const commandBuffer = try context.beginDraw();
        defer context.endDraw() catch {
            @panic("Failed to end draw");
        };
        try coloredVertexPipeline.draw(commandBuffer, trans);
    }
}
