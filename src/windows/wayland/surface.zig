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
    }

    pub fn deinit(self: *LockSurface) void {
        c.ext_session_lock_surface_v1_destroy(self.surface);
    }
};
