const std = @import("std");
const w = @import("wayland_c.zig");
const c = w.c;
const seat = @import("seat.zig");
const WaylandConnection = @import("waylandConnection.zig").WaylandConnection;
const xdg = @import("xdg.zig");
const Surface = @import("surface.zig").Surface;
const st = @import("seat.zig");

pub const WaylandWindow = struct {
    connection: WaylandConnection = .{},

    surface: Surface = undefined,
    xdgSurface: xdg.Surface = xdg.Surface{},
    seat: st.Seat = undefined,

    should_close: bool = false,
    width: u32,
    height: u32,

    pub fn init(width: u32, height: u32) !WaylandWindow {
        return WaylandWindow{
            .width = width,
            .height = height,
        };
    }

    pub fn initConnection(self: *WaylandWindow, allocator: std.mem.Allocator) !void {
        try self.connection.init(allocator, null);

        if (self.connection.compositor == null) return error.NoCompositor;
        if (self.connection.xdgWmBase == null) return error.NoXdgWmBase;
        const wlSeat = self.connection.seat orelse return error.NoWlSeat;
        try self.seat.init(wlSeat);

        std.log.info("Wayland connection established", .{});
    }

    pub fn createWindow(self: *WaylandWindow, title: []const u8) !void {
        if (self.connection.compositor) |compositor| {
            try self.surface.init(compositor);
        } else {
            return error.NoCompositor;
        }

        if (self.connection.xdgWmBase) |wmBase| {
            try self.xdgSurface.init(wmBase, self.surface.surface, title);
        } else {
            return error.NoXdgWmBase;
        }

        self.surface.commit();

        std.log.info("Window created", .{});
    }

    pub fn commit(self: *WaylandWindow) !void {
        self.surface.commit();
        try self.connection.roundtrip();
    }

    pub fn dispatch(self: *WaylandWindow) !void {
        try self.connection.dispatch();

        self.should_close = self.xdgSurface.shouldClose;
        self.width = @intCast(self.xdgSurface.width);
        self.height = @intCast(self.xdgSurface.height);
    }

    pub fn deinit(self: *WaylandWindow) void {
        self.xdgSurface.deinit();
        self.surface.deinit();
        self.connection.deinit();
    }
};
