const std = @import("std");
const builtin = @import("builtin");
const wayland = @import("wayland_c.zig");
const macos = @import("macos.zig");
const vk = @import("vk.zig");
const c = vk.c;

const Platform = enum {
    macos,
    linux,
};
const platform = if (builtin.os.tag == .macos) Platform.macos else Platform.linux;

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
    surface: vk.SurfaceKHR,
    instance: vk.Instance,

    pub fn init(allocator: std.mem.Allocator) !Window {
        const windowHandle = switch (comptime platform) {
            .macos => macos.createMacWindow() orelse @panic("Could not create window"),
            .linux => try wayland.WaylandWindow.init(allocator, 800, 600),
        };

        // Create Vulkan instance
        const app_info = c.VkApplicationInfo{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "Vulkan Triangle",
            .apiVersion = vk.API_VERSION_1_0,
            // .pNext = null,
            // .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
            // .pEngineName = "No Engine",
            // .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        };

        // Simpler extension list for older MoltenVK
        const extensions = if (builtin.os.tag == .macos)
            [_][*:0]const u8{
                c.VK_KHR_SURFACE_EXTENSION_NAME,
                c.VK_EXT_METAL_SURFACE_EXTENSION_NAME,
                c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
            }
        else
            [_][*:0]const u8{
                c.VK_KHR_SURFACE_EXTENSION_NAME,
                c.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
                c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
            };

        //const validationLayers = [_][*:0]const u8{
        //    "VK_LAYER_KHRONOS_validation",
        //};

        const instance_create_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = 0, // Remove portability enumeration flag
            .pApplicationInfo = &app_info,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = extensions.len,
            .ppEnabledExtensionNames = &extensions,
        };

        var instance: c.VkInstance = null;
        try vk.checkResult(c.vkCreateInstance(&instance_create_info, null, &instance));

        var surface: c.VkSurfaceKHR = null;
        switch (comptime platform) {
            .macos => {
                const metal_layer = macos.getMetalLayer(windowHandle);
                const surface_create_info = c.VkMetalSurfaceCreateInfoEXT{
                    .sType = c.VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
                    .pNext = null,
                    .flags = 0,
                    .pLayer = metal_layer,
                };
                try vk.checkResult(c.vkCreateMetalSurfaceEXT(instance, &surface_create_info, null, &surface));
            },
            .linux => {
                // Wayland surface - you'll need wl_display and wl_surface pointers
                if (windowHandle.display) |display| {
                    if (windowHandle.surface) |rawSurface| {
                        std.debug.print("c.VkSurfaceKHR type: {}\n", .{@TypeOf(@as(c.VkSurfaceKHR, undefined))});
                        std.debug.print("vk.SurfaceKHR type: {}\n", .{@TypeOf(@as(vk.SurfaceKHR, undefined))});
                        const displayOpaque: *anyopaque = @ptrCast(display);
                        const surfaceOpaque: *anyopaque = @ptrCast(rawSurface);
                        std.debug.print("Wayland display: {*}\n", .{displayOpaque});
                        std.debug.print("Wayland surface: {*}\n", .{surfaceOpaque});
                        std.debug.print("Surface type: {}\n", .{@TypeOf(rawSurface)});
                        const surface_create_info = c.VkWaylandSurfaceCreateInfoKHR{
                            .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
                            .display = @ptrCast(@alignCast(displayOpaque)),
                            .surface = @ptrCast(@alignCast(surfaceOpaque)),
                            .pNext = null,
                            .flags = 0,
                        };
                        std.debug.print("Display pointer value: 0x{x}\n", .{@intFromPtr(display)});
                        std.debug.print("Surface pointer value: 0x{x}\n", .{@intFromPtr(rawSurface)});
                        std.debug.print("Display after cast: 0x{x}\n", .{@intFromPtr(surface_create_info.display)});
                        std.debug.print("Surface after cast: 0x{x}\n", .{@intFromPtr(surface_create_info.surface)});
                        std.debug.print("Address of surface variable: {*}\n", .{&surface});
                        std.debug.print("Size of VkSurfaceKHR: {}\n", .{@sizeOf(c.VkSurfaceKHR)});
                        //const result = c.vkCreateWaylandSurfaceKHR(instance, &surface_create_info, null, &surface);
                        const vkGetInstanceProcAddr = c.vkGetInstanceProcAddr;

                        const vkCreateWaylandSurfaceKHR_ptr = vkGetInstanceProcAddr(instance, "vkCreateWaylandSurfaceKHR");
                        std.debug.print("Function pointer loaded: {?}\n", .{vkCreateWaylandSurfaceKHR_ptr});

                        if (vkCreateWaylandSurfaceKHR_ptr == null) {
                            return error.WaylandSurfaceExtensionNotAvailable;
                        }

                        std.debug.print("Expected display type: {}\n", .{@TypeOf(@as(c.VkWaylandSurfaceCreateInfoKHR, undefined).display)});
                        std.debug.print("Expected surface type: {}\n", .{@TypeOf(@as(c.VkWaylandSurfaceCreateInfoKHR, undefined).surface)});
                        std.debug.print("Actual display type: {}\n", .{@TypeOf(display)});
                        std.debug.print("Actual rawSurface type: {}\n", .{@TypeOf(rawSurface)});
                        std.debug.print("Extension name: {s}\n", .{c.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME});
                        std.debug.print("Extensions passed to instance:\n", .{});
                        for (extensions) |ext| {
                            std.debug.print("  - {s}\n", .{ext});
                        }
                        std.debug.print("Address where surface will be written: {*}\n", .{&surface});
                        const result = c.vkCreateWaylandSurfaceKHR(instance, &surface_create_info, null, &surface);
                        std.debug.print("Address of surface after call: {*}\n", .{&surface});
                        std.debug.print("Memory at surface location: ", .{});
                        const bytes: [*]const u8 = @ptrCast(&surface);
                        for (0..8) |i| {
                            std.debug.print("{x:0>2} ", .{bytes[i]});
                        }
                        std.debug.print("\n", .{});
                        std.log.debug("Create surface result: {}", .{result});
                        std.debug.print("Surface value after creation: {any}\n", .{surface});
                        std.debug.print("Surface as u64: {x}\n", .{@as(u64, @intFromPtr(surface))});
                    } else @panic("no surface");
                } else @panic("no display");
            },
        }

        return Window{
            .windowHandle = windowHandle,
            .instance = instance,
            .surface = surface,
        };
    }

    pub fn deinit(self: *Window) void {
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
        switch (comptime platform) {
            .macos => {
                macos.releaseMacWindow(self.windowHandle);
            },
            .linux => {
                self.windowHandle.deinit();
            },
        }
    }

    pub fn getWindowSize(self: *const Window) struct { u32, u32 } {
        return getWindowHeight(self.windowHandle);
    }

    pub fn pollEvents(self: *Window) bool {
        switch (comptime platform) {
            .macos => {
                var event: macos.MacEvent = undefined;
                return macos.pollMacEvent(&event);
            },
            .linux => {
                self.windowHandle.dispatch();
                return !self.windowHandle.should_close;
            },
        }
    }
};
