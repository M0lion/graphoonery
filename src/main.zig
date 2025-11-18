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
const platform = @import("platform.zig").platform;
const lock = @import("lockscreen.zig");
const spirv = @import("vulkan/spirv/spirv.zig");

var password = std.mem.zeroes([50]u8);
var passwordCharCount: usize = 0;
var globalAllocator: ?std.mem.Allocator = undefined;

fn key_handler(key: c_uint) void {
    if (key == 28) {
        std.log.debug("Authenticating with password \"{s}\"", .{password});
        if (pam.authenticate(globalAllocator.?, password[0..])) {
            std.log.debug("Success", .{});
        } else {
            std.log.debug("Fail", .{});
        }
        @memset(password[0..], 0);
        passwordCharCount = 0;
    }
}

fn key_string_handler(char: []u8) void {
    for (char) |ch| {
        if (ch == 13) return;
        password[passwordCharCount] = ch;
        passwordCharCount += 1;
    }
}

const vertex = spirv.parseSpriv(shaders.vertex_vert_spv);

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    globalAllocator = allocator;

    for (vertex) |variable| {
        std.log.info("Name: {} {s} - {any}", .{
            variable.id,
            variable.name orelse "NO NAME",
            variable.type,
        });
    }

    std.log.debug("Window init", .{});
    var window = try windows.Window.init();
    try window.finishInit(allocator);
    std.log.debug("Window: {*}", .{&window});
    defer window.deinit();

    if (platform == .linux) {
        window.windowHandle.seat.keyStringHandler = key_string_handler;
        window.windowHandle.seat.keyHandler = key_handler;
    }

    var width, var height = window.getWindowSize();

    std.log.debug("Vulkan init", .{});
    var surfaceData: VulkanContext.SurfaceData = undefined;
    switch (platform) {
        .linux => surfaceData = .{
            .display = window.windowHandle.connection.display,
            .surface = window.windowHandle.surface.surface,
        },
        .macos => surfaceData = window.windowHandle,
    }
    var vulkanContext = try VulkanContext.init(surfaceData, width, height, allocator);
    defer vulkanContext.deinit() catch {
        @panic("Failed to clean up vulkan context");
    };

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
        @panic("Failed to free transform");
    };
    var dodecTransform = try ColoredVertexPipeline.TransformUBO.init(&coloredVertexPipeline);
    defer dodecTransform.deinit() catch |err| {
        std.log.err("Failed to free dodecTransform: {}", .{err});
        @panic("Failed to free dodecTransform");
    };

    // Flush all Wayland requests before rendering
    if (builtin.os.tag != .macos) {
        if (window.windowHandle.connection.display) |display| {
            _ = wayland_c.c.wl_display_flush(display);
        }
    }

    var aspect =
        @as(f32, @floatFromInt(width)) /
        @as(f32, @floatFromInt(height));

    var t = math.Mat4.identity();
    var p = math.Mat4.createPerspective(90, aspect, 0.01, 10);
    var dt = math.Mat4.identity();
    try transform.update(&t, &p);
    try dodecTransform.update(&dt, &p);

    std.log.debug("Main loop", .{});
    // Event loop
    var time: f32 = 0.0;
    while (try window.pollEvents()) {
        width, height = window.getWindowSize();
        t = math.Mat4.createRotation(time * 10, time * 6, time * 30);
        t = math.Mat4.createTranslation(0, 0, -5).multiply(&t);
        t = math.Mat4.createTranslation(-1, 1.5, 0).multiply(&t);
        dt = math.Mat4.createRotation(time * 6, time * 30, time * 10);
        dt = math.Mat4.createTranslation(0, 0, -5).multiply(&dt);
        dt = math.Mat4.createTranslation(1, -1.5, 0).multiply(&dt);
        if (vulkanContext.width != width or vulkanContext.height != height) {
            try vulkanContext.resize(width, height);
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
