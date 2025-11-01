const std = @import("std");
const builtin = @import("builtin");
const Window = @import("../windows/window.zig").Window;
const vk = @import("vk.zig");
const c = vk.c;
const platform = @import("../platform.zig").platform;
const macos = @import("../windows/macos.zig");
const createInstance = @import("instance.zig").createInstance;
const s = @import("surface.zig");
const pDevice = @import("physicalDevice.zig");
const lDevice = @import("logicalDevice.zig");

pub const VulkanContextError = error{
    CouldNotFindPDevice,
};

pub const VulkanContext = struct {
    surface: c.VkSurfaceKHR,
    instance: c.VkInstance,
    physicalDevice: c.VkPhysicalDevice,
    queueFamily: u32,
    logicalDevice: c.VkDevice,
    queue: c.VkQueue,

    pub fn init(window: *Window, allocator: std.mem.Allocator) !VulkanContext {
        const instance = try createInstance(.{
            .name = "Vulkan Test",
        });

        var surface: c.VkSurfaceKHR = null;
        switch (comptime platform) {
            .macos => {
                surface = try s.createMetalSurface(instance, .{ .windowHandle = window.windowHandle });
            },
            .linux => {
                surface = try s.createWaylandSurface(instance, .{
                    .display = window.windowHandle.display,
                    .surface = window.windowHandle.surface,
                });
            },
        }

        const physicalDeviceResult = try pDevice.pickPhysicalDevice(
            instance,
            allocator,
            surface,
        ) orelse {
            return VulkanContextError.CouldNotFindPDevice;
        };

        const physicalDevice = physicalDeviceResult.device;
        const queueFamily = physicalDeviceResult.queue;

        const logicalDevice = try lDevice.createLogicalDevice(physicalDevice, queueFamily);

        var queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(logicalDevice, @intCast(queueFamily), 0, &queue);

        return VulkanContext{
            .instance = instance,
            .surface = surface,
            .physicalDevice = physicalDevice,
            .queueFamily = queueFamily,
            .logicalDevice = logicalDevice,
            .queue = queue,
        };
    }

    pub fn deinit(self: *VulkanContext) void {
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};
