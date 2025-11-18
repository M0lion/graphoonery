const std = @import("std");
const lock = @import("windows/wayland/lockscreen.zig");
const wl = @import("windows/wayland/waylandConnection.zig");
const pam = @import("pam.zig");
const vkC = @import("vulkan/vulkanContext.zig");
const ColoredVertexPipeline = @import("coloredVertexPipeline.zig").ColoredVertexPipeline;
const cube = @import("cube.zig");
const vk = @import("vulkan/vk.zig");
const math = @import("math/index.zig");
const sf = @import("windows/wayland/surface.zig");

var password = std.mem.zeroes([50]u8);
var passwordCharCount: usize = 0;
var globalAllocator: std.mem.Allocator = undefined;

var authenticated = false;

var screens: std.ArrayList(Screen) = undefined;
var sessionLock: lock.SessionLock = undefined;

fn outputAdded(connection: *wl.WaylandConnection, output: *wl.Output, name: u32) void {
    std.log.info("Output added: {}", .{name});
    screens.append(globalAllocator, Screen{}) catch {
        @panic("Failed to add screen");
    };

    screens.items[screens.items.len - 1].init(connection, output, globalAllocator) catch {
        @panic("Failed to init screen");
    };
}

fn outputRemoved(name: u32) void {
    std.log.info("Output removed: {}", .{name});
    var screenIndex: ?usize = null;
    for (screens.items, 0..) |screen, i| {
        if (screen.wlOutput.name == name) {
            screenIndex = i;
        }
    }

    if (screenIndex) |i| {
        screens.items[i].deinit() catch {
            @panic("Cound not deinit screen");
        };

        _ = screens.orderedRemove(i);
    } else {
        @panic("Could not find screen");
    }
}

const Screen = struct {
    context: vkC.VulkanContext = undefined,
    pipe: ColoredVertexPipeline = undefined,
    mesh: ColoredVertexPipeline.Mesh = undefined,
    transform: ColoredVertexPipeline.TransformUBO = undefined,
    wlOutput: *wl.Output = undefined,
    surface: sf.Surface = undefined,
    lockSurface: sf.LockSurface = undefined,

    pub fn init(
        self: *Screen,
        connection: *wl.WaylandConnection,
        wlOutput: *wl.Output,
        allocator: std.mem.Allocator,
    ) !void {
        self.wlOutput = wlOutput;
        const compositor = connection.compositor orelse return error.NoCompositor;

        // Create surface
        try self.surface.init(compositor);

        // Create lockSurface
        try self.lockSurface.init(
            sessionLock.lock,
            self.surface.surface,
            wlOutput.output,
        );

        while (!self.wlOutput.done) {
            try connection.roundtrip();
        }

        self.context = try vkC.VulkanContext.init(
            .{
                .display = connection.display,
                .surface = self.surface.surface,
            },
            @intCast(self.wlOutput.width),
            @intCast(self.wlOutput.height),
            allocator,
        );
        self.pipe = try ColoredVertexPipeline.init(self.context);

        self.mesh = try cube.getCube(&self.pipe);
        self.transform = try ColoredVertexPipeline.TransformUBO.init(&self.pipe);
    }

    pub fn deinit(self: *Screen) !void {
        try self.context.waitDeviceIdle();
        std.log.debug("Freeing mesh", .{});
        self.mesh.deinit();
        std.log.debug("Freeing transform", .{});
        try self.transform.deinit();
        std.log.debug("Freeing pipeline", .{});
        self.pipe.deinit();
        std.log.debug("Freeing context", .{});
        try self.context.deinit();
        self.lockSurface.deinit();
        self.surface.deinit();
    }

    pub fn draw(self: *Screen, time: f32) !void {
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
        if (pam.authenticate(globalAllocator, password[0..])) {
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

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    globalAllocator = allocator;

    std.log.info("Initalizing connection", .{});
    var connection: wl.WaylandConnection = .{};
    try connection.init(allocator, wl.ConnectionListeners{
        .outputRemovedListener = outputRemoved,
    });

    sessionLock.seat.keyHandler = key_handler;
    sessionLock.seat.keyStringHandler = key_string_handler;
    try sessionLock.init(&connection, allocator);

    std.log.info("Initializing screens", .{});
    const outputs = connection.outputs.items;
    screens = try std.ArrayList(Screen).initCapacity(allocator, outputs.len);
    for (outputs) |output| {
        try screens.append(
            allocator,
            Screen{},
        );

        try screens.items[screens.items.len - 1].init(&connection, output, allocator);
    }
    connection.outputAddedListener = outputAdded;

    std.log.info("Waiting for screens to be configured", .{});
    // Wait for surfaces to be configured
    var all_configured = false;
    while (!all_configured) {
        try connection.dispatch();
        all_configured = true;
        for (screens.items) |screen| {
            if (!screen.lockSurface.configured) {
                all_configured = false;
                break;
            }
        }
        std.Thread.sleep(1000 * 10);
    }
    std.log.info("All surfaces configured, starting draw loop", .{});

    var timer = try std.time.Timer.start();
    while (!authenticated) {
        const time: f32 = @as(f32, @floatFromInt(timer.read())) / 10000000000;
        try connection.dispatch();

        for (screens.items, 0..) |*screen, i| {
            if (!screen.lockSurface.configured) continue;
            const random = @as(f32, @floatFromInt((68061571 * i) % 5));
            try screen.draw(time + random);
        }
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    std.log.info("Authentication successful, cleaning up...", .{});

    // Important: Clean up Vulkan contexts before destroying the lock
    for (screens.items) |*screen| {
        try screen.deinit();
    }

    // Give the compositor time to process the unlock
    sessionLock.deinit();
    try connection.roundtrip();

    std.log.info("Lockscreen exited cleanly", .{});
}
