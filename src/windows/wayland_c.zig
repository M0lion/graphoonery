const std = @import("std");

pub const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("xdg-shell-client-protocol.h");
});

pub const WaylandWindow = struct {
    allocator: std.mem.Allocator,
    display: ?*c.wl_display = null,
    registry: ?*c.wl_registry = null,
    compositor: ?*c.wl_compositor = null,
    seat: ?*c.wl_seat = null,
    xdg_wm_base: ?*c.xdg_wm_base = null,

    surface: ?*c.wl_surface = null,
    xdg_surface: ?*c.xdg_surface = null,
    xdg_toplevel: ?*c.xdg_toplevel = null,

    configured: bool = false,
    should_close: bool = false,
    width: u32,
    height: u32,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !WaylandWindow {
        var self = WaylandWindow{
            .allocator = allocator,
            .width = width,
            .height = height,
        };

        try self.initConnection();
        try self.createWindow();

        return self;
    }

    fn initConnection(self: *WaylandWindow) !void {
        global_context = self;

        self.display = c.wl_display_connect(null);
        if (self.display == null) return error.NoDisplay;

        self.registry = c.wl_display_get_registry(self.display);
        if (self.registry == null) return error.NoRegistry;

        _ = c.wl_registry_add_listener(self.registry, &registry_listener, null);
        _ = c.wl_display_roundtrip(self.display);

        if (self.compositor == null) return error.NoCompositor;
        if (self.xdg_wm_base == null) return error.NoXdgWmBase;

        if (self.registry) |r| {
            c.wl_registry_destroy(r);
            self.registry = null;
        }

        std.log.info("Wayland connection established", .{});
    }

    fn createWindow(self: *WaylandWindow) !void {
        self.surface = c.wl_compositor_create_surface(self.compositor);
        if (self.surface == null) return error.NoSurface;

        self.xdg_surface = c.xdg_wm_base_get_xdg_surface(self.xdg_wm_base, self.surface);
        if (self.xdg_surface == null) return error.NoXdgSurface;

        _ = c.xdg_surface_add_listener(self.xdg_surface, &xdg_surface_listener, null);

        self.xdg_toplevel = c.xdg_surface_get_toplevel(self.xdg_surface);
        if (self.xdg_toplevel == null) return error.NoXdgToplevel;

        _ = c.xdg_toplevel_add_listener(self.xdg_toplevel, &xdg_toplevel_listener, null);
        c.xdg_toplevel_set_title(self.xdg_toplevel, "Vulkan Window");

        c.wl_surface_commit(self.surface);

        // while (!self.configured) {
        //     _ = c.wl_display_dispatch(self.display);
        // }

        std.log.info("Window created", .{});
    }

    pub fn dispatch(self: *WaylandWindow) void {
        if (self.display) |display| {
            // Use proper Wayland event loop pattern for multi-queue coordination
            // This is critical when Vulkan creates its own internal event queue
            while (c.wl_display_prepare_read(display) != 0) {
                _ = c.wl_display_dispatch_pending(display);
            }
            _ = c.wl_display_flush(display);
            _ = c.wl_display_read_events(display);
            _ = c.wl_display_dispatch_pending(display);
        }
    }

    pub fn deinit(self: *WaylandWindow) void {
        if (self.xdg_toplevel) |t| c.xdg_toplevel_destroy(t);
        if (self.xdg_surface) |s| c.xdg_surface_destroy(s);
        if (self.surface) |s| c.wl_surface_destroy(s);
        if (self.xdg_wm_base) |base| c.xdg_wm_base_destroy(base);
        if (self.compositor) |comp| c.wl_compositor_destroy(comp);
        // Registry is destroyed in initConnection, no need to destroy again
        if (self.display) |d| c.wl_display_disconnect(d);
    }
};

var global_context: ?*WaylandWindow = null;

// Registry listener
const registry_listener = c.wl_registry_listener{
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

fn registryGlobal(
    data: ?*anyopaque,
    registry: ?*c.wl_registry,
    name: u32,
    interface: [*c]const u8,
    version: u32,
) callconv(.c) void {
    _ = data;
    const ctx = global_context orelse return;

    const interface_str = std.mem.span(interface);

    if (std.mem.eql(u8, interface_str, std.mem.span(c.wl_compositor_interface.name))) {
        ctx.compositor = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_compositor_interface, @min(version, 4)));
    } else if (std.mem.eql(u8, interface_str, std.mem.span(c.xdg_wm_base_interface.name))) {
        ctx.xdg_wm_base = @ptrCast(c.wl_registry_bind(registry, name, &c.xdg_wm_base_interface, @min(version, 1)));
        _ = c.xdg_wm_base_add_listener(ctx.xdg_wm_base, &xdg_wm_base_listener, null);
    } else if (std.mem.eql(u8, interface_str, std.mem.span(c.wl_compositor_interface.name))) {
        ctx.seat = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_seat_interface, @min(version, 1)));
        // c.wl_seat_add_listener(ctx.seat, &seat_base_listener, null);
    }
}

fn registryGlobalRemove(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32) callconv(.c) void {
    _ = data;
    _ = registry;
    _ = name;
}

// XDG WM Base listener
const xdg_wm_base_listener = c.xdg_wm_base_listener{
    .ping = xdgWmBasePing,
};

fn xdgWmBasePing(data: ?*anyopaque, xdg_wm_base: ?*c.xdg_wm_base, serial: u32) callconv(.c) void {
    _ = data;
    c.xdg_wm_base_pong(xdg_wm_base, serial);
}

// XDG Surface listener
const xdg_surface_listener = c.xdg_surface_listener{
    .configure = xdgSurfaceConfigure,
};

fn xdgSurfaceConfigure(data: ?*anyopaque, xdg_surface: ?*c.xdg_surface, serial: u32) callconv(.c) void {
    _ = data;
    const ctx = global_context orelse return;

    c.xdg_surface_ack_configure(xdg_surface, serial);
    ctx.configured = true;
    std.log.info("Surface configured", .{});
}

// XDG Toplevel listener
const xdg_toplevel_listener = c.xdg_toplevel_listener{
    .configure = xdgToplevelConfigure,
    .close = xdgToplevelClose,
};

fn xdgToplevelConfigure(
    data: ?*anyopaque,
    xdg_toplevel: ?*c.xdg_toplevel,
    width: i32,
    height: i32,
    states: ?*c.wl_array,
) callconv(.c) void {
    _ = data;
    _ = xdg_toplevel;
    _ = states;
    const ctx = global_context orelse return;

    if (width > 0 and height > 0) {
        ctx.width = @intCast(width);
        ctx.height = @intCast(height);
        std.log.info("Window resized to {}x{}", .{ ctx.width, ctx.height });
    }
}

fn xdgToplevelClose(data: ?*anyopaque, xdg_toplevel: ?*c.xdg_toplevel) callconv(.c) void {
    _ = data;
    _ = xdg_toplevel;
    const ctx = global_context orelse return;

    std.log.info("Window close requested", .{});
    ctx.should_close = true;
}
