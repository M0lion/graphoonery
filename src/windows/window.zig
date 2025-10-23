const std = @import("std");
const builtin = @import("builtin");
const wayland = @import("wayland.zig");
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
            .pNext = null,
            .pApplicationName = "Vulkan Triangle",
            .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "No Engine",
            .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = vk.API_VERSION_1_0,
        };

        // Simpler extension list for older MoltenVK
        const extensions = if (builtin.os.tag == .macos)
            [_][*:0]const u8{
                c.VK_KHR_SURFACE_EXTENSION_NAME,
                c.VK_EXT_METAL_SURFACE_EXTENSION_NAME,
            }
        else
            [_][*:0]const u8{
                c.VK_KHR_SURFACE_EXTENSION_NAME,
                c.VK_KHR_SURFACE_EXTENSION_NAME,
                c.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
            };

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

        var instance: vk.Instance = undefined;
        try vk.checkResult(c.vkCreateInstance(&instance_create_info, null, &instance));

        var surface: vk.SurfaceKHR = undefined;
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
                    const surface_create_info = c.VkWaylandSurfaceCreateInfoKHR{
                        .display = @ptrCast(display),
                        .flags = 0,
                        .pNext = null,
                        .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
                        .surface = @ptrCast(windowHandle.surface),
                    };
                    try vk.checkResult(c.vkCreateWaylandSurfaceKHR(instance, &surface_create_info, null, &surface));
                } else @panic("wtf");
            },
        }

        return Window{
            .windowHandle = windowHandle,
            .instance = instance,
            .surface = surface,
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

        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }

    pub fn getWindowSize(self: *const Window) struct { u32, u32 } {
        return getWindowHeight(self.windowHandle);
    }

    pub fn pollEvents() bool {
        switch (comptime platform) {
            .macos => {
                var event: macos.MacEvent = undefined;
                return macos.pollMacEvent(&event);
            },
            .linux => {
                return true;
            },
        }
    }
};
