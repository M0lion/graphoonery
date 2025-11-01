const std = @import("std");
const builtin = @import("builtin");
const Window = @import("../windows/window.zig").Window;
const vk = @import("vk.zig");
const c = vk.c;
const platform = @import("../platform.zig").platform;
const macos = @import("../windows/macos.zig");
const createInstance = @import("instance.zig").createInstance;
const s = @import("surface.zig");

pub const VulkanContext = struct {
    surface: vk.SurfaceKHR,
    instance: vk.Instance,

    pub fn init(window: *Window) !VulkanContext {
        const instance = try createInstance(.{
            .name = "Vulkan Test",
        });

        var surface: c.VkSurfaceKHR = null;
        switch (comptime platform) {
            .macos => {
                surface = try s.createMetalSurface(
                    instance,
                    .{
                        .windowHandle = window.windowHandle,
                    },
                );
            },
            .linux => {
                surface = try s.createWaylandSurface(
                    instance,
                    .{
                        .display = window.windowHandle.display,
                        .surface = window.windowHandle.surface,
                    },
                );
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
