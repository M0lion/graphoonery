const std = @import("std");
const w = @import("wayland_c.zig");
const c = w.c;

pub const Surface = struct {
    surface: *c.wl_surface = undefined,

    pub fn init(self: *Surface, compositor: *c.wl_compositor) !void {
        self.surface = c.wl_compositor_create_surface(compositor) orelse return error.NoSurface;
    }

    pub fn commit(self: *Surface) void {
        c.wl_surface_commit(self.surface);
    }

    pub fn deinit(self: *Surface) void {
        c.wl_surface_destroy(self.surface);
    }
};

pub const LockSurface = struct {
    surface: *c.ext_session_lock_surface_v1 = undefined,
    configured: bool = false,

    pub fn init(
        self: *LockSurface,
        lock: *c.ext_session_lock_v1,
        surface: *c.wl_surface,
        output: *c.wl_output,
    ) !void {
        self.surface = c.ext_session_lock_v1_get_lock_surface(
            lock,
            surface,
            output,
        ) orelse return error.NoSurface;
        self.configured = false;
        try w.checkResult(c.ext_session_lock_surface_v1_add_listener(
            self.surface,
            &lockSurfaceListener,
            self,
        ));
    }

    pub fn deinit(self: *LockSurface) void {
        c.ext_session_lock_surface_v1_destroy(self.surface);
    }
};

const lockSurfaceListener = c.ext_session_lock_surface_v1_listener{
    .configure = lockSurfaceConfigure,
};

fn lockSurfaceConfigure(
    data: ?*anyopaque,
    surface: ?*c.ext_session_lock_surface_v1,
    serial: u32,
    width: u32,
    height: u32,
) callconv(.c) void {
    _ = width;
    _ = height;
    const self = @as(*LockSurface, @ptrCast(@alignCast(data.?)));
    c.ext_session_lock_surface_v1_ack_configure(surface, serial);
    self.configured = true;
    std.log.debug("Lock surface configured", .{});
}
