const std = @import("std");
const lock = @import("windows/wayland/lockscreen.zig");
const wl = @import("windows/wayland/waylandConnection.zig");
const pam = @import("pam.zig");
const vkC = @import("vulkan/vulkanContext.zig");
const ColoredVertexPipeline = @import("coloredVertexPipeline.zig").ColoredVertexPipeline;
const cube = @import("cube.zig");
const vk = @import("vulkan/vk.zig");
const math = @import("math/index.zig");

var password = std.mem.zeroes([50]u8);
var passwordCharCount: usize = 0;
var globalAllocator: ?std.mem.Allocator = undefined;

var authenticated = false;

const Screen = struct {
    context: vkC.VulkanContext = undefined,
    pipe: ColoredVertexPipeline = undefined,
    mesh: ColoredVertexPipeline.Mesh = undefined,
    transform: ColoredVertexPipeline.TransformUBO = undefined,
    wlOutput: *wl.Output = undefined,

    pub fn init(self: *Screen, context: vkC.VulkanContext, wlOutput: *wl.Output) !void {
        self.context = context;
        self.wlOutput = wlOutput;
        self.pipe = try ColoredVertexPipeline.init(context);

        self.mesh = try cube.getCube(&self.pipe);
        self.transform = try ColoredVertexPipeline.TransformUBO.init(&self.pipe);
    }

    pub fn deinit(self: *Screen) !void {
        self.mesh.deinit();
        try self.transform.deinit();
        self.context.deinit();
    }

    pub fn draw(self: *Screen, time: f32) !void {
        std.log.debug("Time: {}", .{time});
        const commandBuffer = try self.context.beginDraw();
        const width: u32 = @intCast(self.wlOutput.width);
        const height: u32 = @intCast(self.wlOutput.height);
        if (self.context.width != width or self.context.height != height) {
            try self.context.resize(width, height);
        }
        var t = math.Mat4.createRotation(time * 10, time * 6, time * 30);
        t = math.Mat4.createTranslation(0, 0, -5).multiply(&t);
        const aspect =
            @as(f32, @floatFromInt(width)) /
            @as(f32, @floatFromInt(height));
        var p = math.Mat4.createPerspective(90, aspect, 0.01, 10);
        try self.transform.update(&t, &p);
        try self.pipe.draw(commandBuffer, &self.transform, &self.mesh);
        try self.context.endDraw();
    }
};

fn key_handler(key: c_uint) void {
    if (key == 28) {
        std.log.debug("Authenticating with password \"{s}\"", .{password});
        if (pam.authenticate(globalAllocator.?, password[0..])) {
            std.log.debug("Success", .{});
            authenticated = true;
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

pub fn startLockscreen() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    globalAllocator = allocator;

    var connection: wl.WaylandConnection = undefined;
    try connection.init(allocator);

    var lockscreen: lock.SessionLock = undefined;
    lockscreen.seat.keyHandler = key_handler;
    lockscreen.seat.keyStringHandler = key_string_handler;
    try lockscreen.init(&connection, allocator);

    const outputs = lockscreen.outputs.items;
    var screens = try std.ArrayList(Screen).initCapacity(allocator, outputs.len);
    for (outputs) |output| {
        const context = try vkC.VulkanContext.init(
            .{
                .display = connection.display,
                .surface = output.surface.surface,
            },
            @intCast(output.wlOutput.width),
            @intCast(output.wlOutput.height),
            allocator,
        );

        try screens.append(
            allocator,
            Screen{},
        );

        try screens.items[screens.items.len - 1].init(context, output.wlOutput);
    }

    // Wait for surfaces to be configured
    var all_configured = false;
    while (!all_configured) {
        try connection.dispatch();
        all_configured = true;
        for (outputs) |output| {
            if (!output.lockSurface.configured) {
                all_configured = false;
                break;
            }
        }
        std.Thread.sleep(1000 * 10);
    }
    std.log.debug("All surfaces configured, starting draw loop", .{});

    var timer = try std.time.Timer.start();
    while (!authenticated) {
        const time: f32 = @as(f32, @floatFromInt(timer.read())) / 10000000000;
        try connection.dispatch();

        for (screens.items, 0..) |*screen, i| {
            const random = @as(f32, @floatFromInt((68061571 * i) % 5));
            try screen.draw(time + random);
        }
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    std.log.debug("Authentication successful, cleaning up...", .{});

    // Important: Clean up Vulkan contexts before destroying the lock
    for (screens.items) |*screen| {
        try screen.deinit();
    }

    // Give the compositor time to process the unlock
    lockscreen.deinit();
    try connection.roundtrip();

    std.log.debug("Lockscreen exited cleanly", .{});
}
