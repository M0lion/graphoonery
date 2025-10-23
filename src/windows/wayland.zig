const std = @import("std");
const wayland = @import("wayland");

const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

pub const OutputInfo = struct {
    output: *wl.Output,
    name: []const u8,
    description: []const u8,
    width: i32 = 0,
    height: i32 = 0,

    pub fn deinit(self: *OutputInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
    }
};

pub const WaylandWindow = struct {
    allocator: std.mem.Allocator,

    // Wayland globals
    display: ?*wl.Display = null,
    registry: ?*wl.Registry = null,
    compositor: ?*wl.Compositor = null,
    shm: ?*wl.Shm = null,
    layer_shell: ?*zwlr.LayerShellV1 = null,
    outputs: std.ArrayListUnmanaged(OutputInfo) = .{},
    selected_output: ?*wl.Output = null,

    // Surface state
    surface: ?*wl.Surface = null,
    layer_surface: ?*zwlr.LayerSurfaceV1 = null,
    configured: bool = false,

    // Note: SHM buffer removed for pure OpenGL rendering
    width: u32,
    height: u32,

    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !WaylandWindow {
        var self = WaylandWindow{
            .allocator = allocator,
            .width = width,
            .height = height,
        };

        // Perform initialization (no SHM buffer for OpenGL)
        try self.initConnection();
        try self.createLayerSurface();

        return self;
    }

    pub fn deinit(self: *WaylandWindow) void {
        self.cleanup();
    }

    fn initConnection(self: *WaylandWindow) !void {
        // Set global context for listeners
        global_wayland_context = self;

        // Connect to display
        self.display = wl.Display.connect(null) catch |err| {
            std.log.err("Failed to connect to Wayland display: {}", .{err});
            return err;
        };
        std.log.info("Connected to Wayland display", .{});

        // Get registry
        self.registry = try self.display.?.getRegistry();
        self.registry.?.setListener(*wl.Registry, registryListener, @ptrCast(self.registry.?));

        // Roundtrip to get globals
        _ = self.display.?.roundtrip();

        if (self.compositor == null) {
            std.log.err("Compositor not available", .{});
            return error.CompositorNotAvailable;
        }

        if (self.shm == null) {
            std.log.err("Shared memory not available", .{});
            return error.ShmNotAvailable;
        }

        if (self.layer_shell == null) {
            std.log.err("Layer shell not available", .{});
            return error.LayerShellNotAvailable;
        }

        std.log.info("Got required globals", .{});
    }

    fn selectOutput(self: *WaylandWindow) void {
        // For now, select the first output
        // TODO: Add configuration to select by name or index
        if (self.outputs.items.len > 0) {
            self.selected_output = self.outputs.items[0].output;
            std.log.info("Selected output: '{s}'", .{self.outputs.items[0].name});
        } else {
            std.log.warn("No outputs available", .{});
        }
    }

    fn createLayerSurface(self: *WaylandWindow) !void {
        // Select which output to use
        self.selectOutput();

        // Create surface
        self.surface = try self.compositor.?.createSurface();
        std.log.info("Created surface", .{});

        // Create layer surface bound to selected output
        self.layer_surface = try self.layer_shell.?.getLayerSurface(self.surface.?, self.selected_output, // Bind to specific output
            zwlr.LayerShellV1.Layer.top, // Top layer for status bar
            "zig-bar" // Namespace
        );

        // Set layer surface listener
        self.layer_surface.?.setListener(*zwlr.LayerSurfaceV1, layerSurfaceListener, @ptrCast(self.layer_surface.?));

        // Configure layer surface for a top bar
        self.layer_surface.?.setSize(0, self.height); // 0 width = full screen, 80px height
        self.layer_surface.?.setAnchor(.{ .top = true, .left = true, .right = true }); // Anchor to top edge
        self.layer_surface.?.setExclusiveZone(@intCast(self.height));
        self.layer_surface.?.setKeyboardInteractivity(.none); // No keyboard focus needed

        // Commit the surface configuration
        self.surface.?.commit();

        // Wait for configure event
        while (!self.configured) {
            const result = self.display.?.dispatch();
            _ = result;
        }

        std.log.info("Layer surface created and configured", .{});
    }

    // SHM buffer creation removed for pure OpenGL rendering

    pub fn present(self: *WaylandWindow) void {
        // For OpenGL rendering, EGL handles the buffer presentation
        // We just need to commit the surface
        if (self.surface) |surface| {
            surface.commit();
        }
    }

    pub fn dispatch(self: *WaylandWindow) void {
        if (self.display) |display| {
            _ = display.dispatch();
            _ = display.flush();
        }
    }

    fn cleanup(self: *WaylandWindow) void {
        std.log.info("Cleaning up Wayland resources...", .{});

        // Clean up outputs
        for (self.outputs.items) |*output_info| {
            output_info.deinit(self.allocator);
        }
        self.outputs.deinit(self.allocator);

        // Clean up Wayland objects (no SHM buffer to clean)
        if (self.layer_surface) |ls| ls.destroy();
        if (self.surface) |s| s.destroy();
        if (self.shm) |s| s.destroy();
        if (self.layer_shell) |ls| ls.destroy();
        if (self.compositor) |c| c.destroy();
        if (self.registry) |r| r.destroy();
        if (self.display) |d| d.disconnect();
    }
};

// Global state to access the context from listeners
var global_wayland_context: ?*WaylandWindow = null;

// Registry event handler
fn registryListener(reg: *wl.Registry, event: wl.Registry.Event, data: *wl.Registry) void {
    _ = data;
    const ctx = global_wayland_context orelse return;

    switch (event) {
        .global => |global| {
            const interface_name = std.mem.span(global.interface);

            if (std.mem.eql(u8, interface_name, std.mem.span(wl.Compositor.interface.name))) {
                ctx.compositor = reg.bind(global.name, wl.Compositor, @min(global.version, wl.Compositor.generated_version)) catch return;
                std.log.info("Bound compositor", .{});
            } else if (std.mem.eql(u8, interface_name, std.mem.span(wl.Shm.interface.name))) {
                ctx.shm = reg.bind(global.name, wl.Shm, @min(global.version, wl.Shm.generated_version)) catch return;
                std.log.info("Bound shm", .{});
            } else if (std.mem.eql(u8, interface_name, std.mem.span(wl.Output.interface.name))) {
                const output = reg.bind(global.name, wl.Output, @min(global.version, wl.Output.generated_version)) catch return;
                output.setListener(*wl.Output, outputListener, @ptrCast(output));

                // Add to outputs list with empty name/description (will be filled by events)
                const output_info = OutputInfo{
                    .output = output,
                    .name = ctx.allocator.dupe(u8, "") catch return,
                    .description = ctx.allocator.dupe(u8, "") catch return,
                };
                ctx.outputs.append(ctx.allocator, output_info) catch return;
                std.log.info("Bound output #{} with listener", .{ctx.outputs.items.len});
            } else if (std.mem.eql(u8, interface_name, std.mem.span(zwlr.LayerShellV1.interface.name))) {
                ctx.layer_shell = reg.bind(global.name, zwlr.LayerShellV1, @min(global.version, zwlr.LayerShellV1.generated_version)) catch return;
                std.log.info("Bound layer shell", .{});
            }
        },
        .global_remove => |global_remove| {
            std.log.info("Global removed: {}", .{global_remove.name});

            // Note: We don't destroy our output reference here because:
            // 1. The output might be temporarily powered off, not permanently removed
            // 2. Layer shell surfaces can persist without specific output binding
            // 3. When output comes back, compositor will handle surface restoration
        },
    }
}

// Output event handler
fn outputListener(output: *wl.Output, event: wl.Output.Event, data: *wl.Output) void {
    _ = data;
    const ctx = global_wayland_context orelse return;

    // Find the output info for this output
    var output_info: ?*OutputInfo = null;
    for (ctx.outputs.items) |*info| {
        if (info.output == output) {
            output_info = info;
            break;
        }
    }

    switch (event) {
        .geometry => |geom| {
            std.log.info("Output geometry: {}x{} at {},{}", .{ geom.physical_width, geom.physical_height, geom.x, geom.y });
        },
        .mode => |mode| {
            std.log.info("Output mode: {}x{} @ {}Hz (flags: {})", .{ mode.width, mode.height, mode.refresh, mode.flags });
            if (output_info) |info| {
                info.width = mode.width;
                info.height = mode.height;
            }
        },
        .done => {
            if (output_info) |info| {
                std.log.info("Output '{s}' configured: {s} ({}x{})", .{ info.name, info.description, info.width, info.height });
            }
        },
        .scale => |scale| {
            std.log.info("Output scale: {}", .{scale.factor});
        },
        .name => |name| {
            if (output_info) |info| {
                ctx.allocator.free(info.name);
                info.name = ctx.allocator.dupe(u8, std.mem.span(name.name)) catch return;
                std.log.info("Output name: {s}", .{info.name});
            }
        },
        .description => |desc| {
            if (output_info) |info| {
                ctx.allocator.free(info.description);
                info.description = ctx.allocator.dupe(u8, std.mem.span(desc.description)) catch return;
                std.log.info("Output description: {s}", .{info.description});
            }
        },
    }
}

// Layer surface event handler
fn layerSurfaceListener(layer_surf: *zwlr.LayerSurfaceV1, event: zwlr.LayerSurfaceV1.Event, data: *zwlr.LayerSurfaceV1) void {
    _ = data;
    const ctx = global_wayland_context orelse return;

    switch (event) {
        .configure => |configure| {
            layer_surf.ackConfigure(configure.serial);
            ctx.width = configure.width;
            ctx.height = configure.height;
            ctx.configured = true;
            std.log.info("Layer surface configured: {}x{}", .{ configure.width, configure.height });
        },
        .closed => {
            std.log.info("Layer surface closed", .{});
            ctx.configured = false;
        },
    }
}
