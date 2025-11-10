const std = @import("std");
const w = @import("wayland_c.zig");
const c = w.c;

pub const Surface = struct {
    surface: *c.xdg_surface = undefined,
    topLevel: *c.xdg_toplevel = undefined,

    width: i32 = 0,
    height: i32 = 0,
    shouldClose: bool = false,

    pub fn init(
        self: *Surface,
        xdgWmBase: *c.xdg_wm_base,
        surface: *c.wl_surface,
        title: []const u8,
    ) !void {
        self.surface = c.xdg_wm_base_get_xdg_surface(xdgWmBase, surface) orelse
            return error.NoXdgSurface;
        try w.checkResult(c.xdg_surface_add_listener(self.surface, &xdg_surface_listener, self));

        self.topLevel = c.xdg_surface_get_toplevel(self.surface) orelse
            return error.NoTopLevel;
        try w.checkResult(c.xdg_toplevel_add_listener(self.topLevel, &xdg_toplevel_listener, self));

        c.xdg_toplevel_set_title(self.topLevel, title.ptr);
    }

    pub fn deinit(self: *Surface) void {
        c.xdg_toplevel_destroy(self.topLevel);
        c.xdg_surface_destroy(self.surface);
    }
};

// XDG Surface Listener
const xdg_surface_listener = c.xdg_surface_listener{
    .configure = xdgSurfaceConfigure,
};

fn xdgSurfaceConfigure(_: ?*anyopaque, xdgSurface: ?*c.xdg_surface, serial: u32) callconv(.c) void {
    c.xdg_surface_ack_configure(xdgSurface, serial);
    std.log.info("Surface configured", .{});
}

// XDG Toplevel Listener
const xdg_toplevel_listener = c.xdg_toplevel_listener{
    .configure = xdgToplevelConfigure,
    .close = xdgToplevelClose,
    .configure_bounds = xdgTopeLevelConfigureBounds,
    .wm_capabilities = xdgTopeLevelCapabilities,
};

fn xdgToplevelConfigure(
    data: ?*anyopaque,
    xdg_toplevel: ?*c.xdg_toplevel,
    width: i32,
    height: i32,
    states: ?*c.wl_array,
) callconv(.c) void {
    _ = xdg_toplevel;
    _ = states;
    const surface = @as(?*Surface, @ptrCast(@alignCast(data))) orelse return;

    surface.width = width;
    surface.height = height;
    std.log.info("Window resized to {}x{}", .{ width, height });
}

fn xdgTopeLevelConfigureBounds(
    _: ?*anyopaque,
    _: ?*c.xdg_toplevel,
    width: c_int,
    height: c_int,
) callconv(.c) void {
    std.log.debug("XDG Top Level Configure Bounds: {}:{}", .{ width, height });
}

fn xdgTopeLevelCapabilities(
    _: ?*anyopaque,
    _: ?*c.xdg_toplevel,
    _: [*c]c.struct_wl_array,
) callconv(.c) void {
    std.log.debug("XDG Top Level Capabilities", .{});
}

fn xdgToplevelClose(data: ?*anyopaque, _: ?*c.xdg_toplevel) callconv(.c) void {
    var surface: *Surface = @ptrCast(@alignCast(data));
    surface.shouldClose = true;
}
