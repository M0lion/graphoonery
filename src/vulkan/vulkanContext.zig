const std = @import("std");
const builtin = @import("builtin");
const Window = @import("../windows/window.zig").Window;
const vk = @import("vk.zig");
const c = vk.c;
const platform = @import("../platform.zig").platform;
const macos = @import("../windows/macos.zig");

pub const VulkanContext = struct {
    surface: vk.SurfaceKHR,
    instance: vk.Instance,

    pub fn init(window: *Window) !VulkanContext {
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

        const layers = [_][*:0]const u8{
            "VK_LAYER_KHRONOS_validation",
            "VK_LAYER_KHRONOS_profiles",
        };

        const instance_create_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = 0, // Remove portability enumeration flag
            .pApplicationInfo = &app_info,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = &layers,
            .enabledExtensionCount = extensions.len,
            .ppEnabledExtensionNames = &extensions,
        };

        std.log.debug("Creating instance", .{});
        var instance: c.VkInstance = null;
        try vk.checkResult(c.vkCreateInstance(&instance_create_info, null, &instance));

        var surface: c.VkSurfaceKHR = null;
        switch (comptime platform) {
            .macos => {
                const metal_layer = macos.getMetalLayer(window.windowHandle);
                const surface_create_info = c.VkMetalSurfaceCreateInfoEXT{
                    .sType = c.VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
                    .pNext = null,
                    .flags = 0,
                    .pLayer = metal_layer,
                };
                try vk.checkResult(c.vkCreateMetalSurfaceEXT(instance, &surface_create_info, null, &surface));
            },
            .linux => {
                const surface_create_info = c.VkWaylandSurfaceCreateInfoKHR{
                    .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
                    .display = @ptrCast(@alignCast(window.windowHandle.display)),
                    .surface = @ptrCast(@alignCast(window.windowHandle.surface)),
                    .pNext = null,
                    .flags = 0,
                };
                try vk.checkResult(c.vkCreateWaylandSurfaceKHR(instance, &surface_create_info, null, &surface));
            },
        }

        return VulkanContext{
            .instance = instance,
            .surface = surface,
        };
    }

    pub fn deinit(self: *VulkanContext) void {
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};
