const std = @import("std");
const builtin = @import("builtin");
const wayland = @import("wayland_c.zig");
const macos = @import("macos.zig");
const p = @import("../platform.zig");
const platform = p.platform;

const WindowHandle = switch (platform) {
    .macos => *anyopaque,
    .linux => wayland.WaylandWindow,
};

fn getWindowHeight(windowHandle: WindowHandle) struct { u32, u32 } {
    switch (comptime platform) {
        .macos => {
            var width: c_int = 0;
            var height: c_int = 0;
            macos.getWindowSize(windowHandle, &width, &height);
            return .{
                @intCast(width),
                @intCast(height),
            };
        },
        .linux => {
            return .{
                windowHandle.width,
                windowHandle.height,
            };
        },
    }
}

pub const Window = struct {
    windowHandle: WindowHandle,

    pub fn init(allocator: std.mem.Allocator) !Window {
        const windowHandle = switch (comptime platform) {
            .macos => macos.createMacWindow() orelse @panic("Could not create window"),
            .linux => try wayland.WaylandWindow.init(allocator, 800, 600),
        };

        return Window{
            .windowHandle = windowHandle,
        };
    }

    pub fn deinit(self: *Window) void {
        switch (comptime platform) {
            .macos => {
                macos.releaseMacWindow(self.windowHandle);
            },
            .linux => {
                self.windowHandle.deinit();
            },
        }
    }

    pub fn finishInit(self: *Window) !void {
        switch (comptime platform) {
            .macos => {},
            .linux => {
                try self.windowHandle.initConnection();
                try self.windowHandle.createWindow();
            },
        }
    }

    pub fn getWindowSize(self: *const Window) struct { u32, u32 } {
        return getWindowHeight(self.windowHandle);
    }

    pub fn commit(self: *Window) void {
        switch (comptime platform) {
            .linux => {
                self.windowHandle.commit();
            },
            .macos => {},
        }
    }

    pub fn pollEvents(self: *Window) bool {
        switch (comptime platform) {
            .macos => {
                var event: macos.MacEvent = undefined;
                return macos.pollMacEvent(&event);
            },
            .linux => {
                self.windowHandle.dispatch();
                std.log.debug("{*} - {}", .{ &self.windowHandle, self.windowHandle.should_close });
                return !self.windowHandle.should_close;
            },
        }
    }
};
