const std = @import("std");
const w = @import("wayland_c.zig");
const c = w.c;

pub const Output = struct {
    output: *c.wl_output,
    name: u32,
    width: i32 = 0,
    height: i32 = 0,
    done: bool = false,
};

pub const WaylandConnection = struct {
    allocator: std.mem.Allocator = undefined,

    display: ?*c.wl_display = null,
    registry: ?*c.wl_registry = null,

    compositor: ?*c.wl_compositor = null,
    xdgWmBase: ?*c.xdg_wm_base = null,
    lockscreenManager: ?*c.ext_session_lock_manager_v1 = null,
    seat: ?*c.wl_seat = null,

    outputs: std.ArrayList(*Output) = undefined,

    pub fn init(self: *WaylandConnection, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.outputs = try std.ArrayList(*Output).initCapacity(allocator, 1);

        self.display = c.wl_display_connect(null);
        if (self.display == null) return error.NoDisplay;

        self.registry = c.wl_display_get_registry(self.display);
        if (self.registry == null) return error.NoRegistry;

        try w.checkResult(c.wl_registry_add_listener(self.registry, &registryListener, self));
        try self.roundtrip();

        if (self.compositor == null) return error.NoCompositor;
        if (self.xdgWmBase == null) return error.NoXdgWmBase;
    }

    pub fn roundtrip(self: *WaylandConnection) !void {
        std.log.debug("Starting roundtrip", .{});
        const result = c.wl_display_roundtrip(self.display);
        if (result < 0) {
            std.log.err("Wayland roundtrip error: {}", .{result});
            return error.Roundtrip;
        }
        std.log.debug("Roundtrip {}", .{result});
    }

    pub fn dispatch(self: *WaylandConnection) !void {
        const display = self.display orelse return error.NoDisplay;
        while (c.wl_display_prepare_read(display) != 0) {
            _ = c.wl_display_dispatch_pending(display);
        }
        _ = c.wl_display_flush(display);
        try w.checkResult(c.wl_display_read_events(display));
        _ = c.wl_display_dispatch_pending(display);
    }

    pub fn deinit(self: *WaylandConnection) void {
        for (self.outputs.items) |output| {
            self.allocator.destroy(output);
        }
        self.outputs.deinit(self.allocator);
        if (self.xdgWmBase) |base| c.xdg_wm_base_destroy(base);
        if (self.compositor) |comp| c.wl_compositor_destroy(comp);
        if (self.display) |d| c.wl_display_disconnect(d);
    }
};

const registryListener = c.wl_registry_listener{
    .global = registryGlobal,
};

fn registryGlobal(
    data: ?*anyopaque,
    registry: ?*c.wl_registry,
    name: u32,
    interface: [*c]const u8,
    version: u32,
) callconv(.c) void {
    const connection: *WaylandConnection = @ptrCast(@alignCast(data));

    const interfaceName = std.mem.span(interface);
    if (cmpInterfaceName(interfaceName, c.wl_compositor_interface.name)) {
        connection.compositor = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_compositor_interface, version));
    } else if (cmpInterfaceName(interfaceName, c.xdg_wm_base_interface.name)) {
        connection.xdgWmBase = @ptrCast(c.wl_registry_bind(registry, name, &c.xdg_wm_base_interface, version));
        w.checkResult(c.xdg_wm_base_add_listener(
            connection.xdgWmBase,
            &xdgWmBaseListener,
            null,
        )) catch |err| {
            std.log.err("Error: {}", .{err});
            @panic("registry global fail");
        };
    } else if (cmpInterfaceName(interfaceName, c.ext_session_lock_manager_v1_interface.name)) {
        connection.lockscreenManager = @ptrCast(c.wl_registry_bind(registry, name, &c.ext_session_lock_manager_v1_interface, version));
    } else if (cmpInterfaceName(interfaceName, c.wl_seat_interface.name)) {
        connection.seat = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_seat_interface, version));
    } else if (cmpInterfaceName(interfaceName, c.wl_output_interface.name)) {
        const output = @as(*c.wl_output, @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &c.wl_output_interface,
            version,
        )));

        const newOutput = connection.allocator.create(Output) catch {
            @panic("Alloc fail");
        };
        newOutput.* = Output{
            .name = name,
            .output = output,
        };
        connection.outputs.append(connection.allocator, newOutput) catch |err| {
            std.log.err("Failed to append output {}", .{err});
            @panic("Output fail");
        };
        w.checkResult(c.wl_output_add_listener(
            output,
            &outputListener,
            connection.outputs.items[connection.outputs.items.len - 1],
        )) catch |err| {
            std.log.err("Add output listener error: {}", .{err});
            @panic("Failed to add output listener");
        };
    }
}

fn cmpInterfaceName(name: []const u8, targetName: [*c]const u8) bool {
    return std.mem.eql(u8, name, std.mem.span(targetName));
}

const xdgWmBaseListener = c.xdg_wm_base_listener{
    .ping = xdgWmBasePing,
};

fn xdgWmBasePing(_: ?*anyopaque, xdg_wm_base: ?*c.xdg_wm_base, serial: u32) callconv(.c) void {
    c.xdg_wm_base_pong(xdg_wm_base, serial);
}

// OutputListener
const outputListener = c.struct_wl_output_listener{
    .geometry = outputGeometry,
    .mode = outputMode,
    .done = outputDone,
    .scale = outputScale,
    .description = outputDescription,
    .name = outputName,
};

fn outputGeometry(
    _: ?*anyopaque,
    _: ?*c.wl_output,
    _: i32, // x
    _: i32, // y
    _: i32, // physical_width
    _: i32, // physical_height
    _: i32, // subpixel
    _: [*c]const u8, // make
    _: [*c]const u8, // model
    _: i32, // transform
) callconv(.c) void {
    // For lockscreen, we primarily care about the mode (resolution) which comes in outputMode
    // Physical dimensions and transform can be used for advanced layout but aren't critical
}

fn outputMode(
    data: ?*anyopaque,
    _: ?*c.wl_output,
    _: u32, // flags
    width: i32,
    height: i32,
    _: i32, // refresh
) callconv(.c) void {
    // Store the output mode (resolution)
    // You'll want to use this width/height when creating lockscreen surfaces for this output
    const output: *Output = @ptrCast(@alignCast(data));

    output.width = width;
    output.height = height;
    // TODO: Store these dimensions in your Output struct for later use
}

fn outputDone(
    data: ?*anyopaque,
    _: ?*c.wl_output,
) callconv(.c) void {
    const output: *Output = @ptrCast(@alignCast(data));
    output.done = true;
    std.log.debug("Output done {}", .{output.name});
}

fn outputScale(
    _: ?*anyopaque,
    _: ?*c.wl_output,
    factor: i32,
) callconv(.c) void {
    // Handle HiDPI scaling
    _ = factor;
    // TODO: Store scale factor for proper surface sizing
}

fn outputDescription(
    _: ?*anyopaque,
    _: ?*c.wl_output,
    description: [*c]const u8,
) callconv(.c) void {
    std.log.debug("Output: {s}", .{description});
}

fn outputName(
    _: ?*anyopaque,
    _: ?*c.wl_output,
    name: [*c]const u8,
) callconv(.c) void {
    std.log.debug("Output Name: {s}", .{name});
}
