const std = @import("std");
const lock = @import("windows/wayland/lockscreen.zig");
const wl = @import("windows/wayland/waylandConnection.zig");
const pam = @import("pam.zig");
const vkC = @import("vulkan/vulkanContext.zig");

var password = std.mem.zeroes([50]u8);
var passwordCharCount: usize = 0;
var globalAllocator: ?std.mem.Allocator = undefined;

var authenticated = false;

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
    var vulkans = try std.ArrayList(vkC.VulkanContext).initCapacity(allocator, outputs.len);
    for (outputs) |output| {
        try vulkans.append(allocator, try vkC.VulkanContext.init(
            .{
                .display = connection.display,
                .surface = output.surface.surface,
            },
            @intCast(output.wlOutput.width),
            @intCast(output.wlOutput.height),
            allocator,
        ));
    }
    defer for (vulkans.items) |*vulkan| {
        vulkan.deinit();
    };

    while (!authenticated) {
        try connection.dispatch();

        for (vulkans.items) |*context| {
            _ = try context.beginDraw();
            defer context.endDraw() catch {
                @panic("Failed to end draw");
            };
        }
        std.Thread.sleep(1000 * 50);
    }
}
