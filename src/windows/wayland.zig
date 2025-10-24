const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;

pub const WaylandWindow = struct {
    allocator: std.mem.Allocator,
    display: ?*wl.Display = null,
    registry: ?*wl.Registry = null,
    compositor: ?*wl.Compositor = null,
    xdg_wm_base: ?*xdg.WmBase = null,

    surface: ?*wl.Surface = null,
    xdg_surface: ?*xdg.Surface = null,
    xdg_toplevel: ?*xdg.Toplevel = null,

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

        self.display = try wl.Display.connect(null);
        self.registry = try self.display.?.getRegistry();
        self.registry.?.setListener(*wl.Registry, registryListener, @ptrCast(self.registry.?));

        _ = self.display.?.roundtrip();

        if (self.compositor == null) return error.NoCompositor;
        if (self.xdg_wm_base == null) return error.NoXdgWmBase;

        std.log.info("Wayland connection established", .{});
    }

    fn createWindow(self: *WaylandWindow) !void {
        self.surface = try self.compositor.?.createSurface();

        self.xdg_surface = try self.xdg_wm_base.?.getXdgSurface(self.surface.?);
        self.xdg_surface.?.setListener(*xdg.Surface, xdgSurfaceListener, @ptrCast(self.xdg_surface.?));

        self.xdg_toplevel = try self.xdg_surface.?.getToplevel();
        self.xdg_toplevel.?.setListener(*xdg.Toplevel, xdgToplevelListener, @ptrCast(self.xdg_toplevel.?));
        self.xdg_toplevel.?.setTitle("Vulkan Window");

        self.surface.?.commit();

        while (!self.configured) {
            _ = self.display.?.dispatch();
        }

        std.log.info("Window created", .{});
    }

    pub fn dispatch(self: *WaylandWindow) void {
        if (self.display) |display| {
            _ = display.dispatchPending();
            _ = display.flush();
        }
    }

    pub fn deinit(self: *WaylandWindow) void {
        if (self.xdg_toplevel) |t| t.destroy();
        if (self.xdg_surface) |s| s.destroy();
        if (self.surface) |s| s.destroy();
        if (self.xdg_wm_base) |base| base.destroy();
        if (self.compositor) |c| c.destroy();
        if (self.registry) |r| r.destroy();
        if (self.display) |d| d.disconnect();
    }
};

var global_context: ?*WaylandWindow = null;

fn registryListener(reg: *wl.Registry, event: wl.Registry.Event, data: *wl.Registry) void {
    _ = data;
    const ctx = global_context orelse return;

    switch (event) {
        .global => |global| {
            const name = std.mem.span(global.interface);

            if (std.mem.eql(u8, name, std.mem.span(wl.Compositor.interface.name))) {
                ctx.compositor = reg.bind(global.name, wl.Compositor, @min(global.version, wl.Compositor.generated_version)) catch return;
            } else if (std.mem.eql(u8, name, std.mem.span(xdg.WmBase.interface.name))) {
                ctx.xdg_wm_base = reg.bind(global.name, xdg.WmBase, @min(global.version, xdg.WmBase.generated_version)) catch return;
                ctx.xdg_wm_base.?.setListener(*xdg.WmBase, wmBaseListener, @ptrCast(ctx.xdg_wm_base.?));
            }
        },
        .global_remove => {},
    }
}

fn wmBaseListener(base: *xdg.WmBase, event: xdg.WmBase.Event, data: *xdg.WmBase) void {
    _ = data;
    switch (event) {
        .ping => |ping| base.pong(ping.serial),
    }
}

fn xdgSurfaceListener(surf: *xdg.Surface, event: xdg.Surface.Event, data: *xdg.Surface) void {
    _ = data;
    const ctx = global_context orelse return;

    switch (event) {
        .configure => |configure| {
            surf.ackConfigure(configure.serial);
            ctx.configured = true;
            std.log.info("Surface configured", .{});
        },
    }
}

fn xdgToplevelListener(toplevel: *xdg.Toplevel, event: xdg.Toplevel.Event, data: *xdg.Toplevel) void {
    _ = data;
    _ = toplevel;
    const ctx = global_context orelse return;

    switch (event) {
        .configure => |configure| {
            if (configure.width > 0 and configure.height > 0) {
                ctx.width = @intCast(configure.width);
                ctx.height = @intCast(configure.height);
                std.log.info("Window resized to {}x{}", .{ ctx.width, ctx.height });
            }
        },
        .close => {
            std.log.info("Window close requested", .{});
            ctx.should_close = true;
        },
    }
}
