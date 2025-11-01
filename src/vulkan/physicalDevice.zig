const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;

const PysicalDevicePick = struct {
    device: c.VkPhysicalDevice,
    queue: u32,
};

pub fn pickPhysicalDevice(instance: c.VkInstance, allocator: std.mem.Allocator, surface: c.VkSurfaceKHR) !?PysicalDevicePick {
    var deviceCount: u32 = 0;
    try vk.checkResult(c.vkEnumeratePhysicalDevices(instance, &deviceCount, null));
    const physicalDevices = try allocator.alloc(c.VkPhysicalDevice, deviceCount);
    try vk.checkResult(c.vkEnumeratePhysicalDevices(instance, &deviceCount, physicalDevices.ptr));
    std.log.info("{}", .{deviceCount});

    var physicalDeviceIndex: ?usize = null;

    var graphicsFamily: ?usize = null;
    var presentFamily: ?usize = null;
    var physicalDevice: c.VkPhysicalDevice = undefined;
    for (physicalDevices, 0..) |device, deviceIndex| {
        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(device, &properties);
        std.log.info("{s}", .{properties.deviceName});

        var queueFamilyCount: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
        const queueFamilies = try allocator.alloc(c.VkQueueFamilyProperties, queueFamilyCount);
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);

        // Get queue families
        for (queueFamilies, 0..) |family, i| {
            if (family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
                graphicsFamily = i;
            }

            var presentSupport: c.VkBool32 = c.VK_FALSE;
            try vk.checkResult(c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface.?, &presentSupport));
            if (presentSupport == c.VK_TRUE) {
                presentFamily = i;
            }

            if (graphicsFamily.? == presentFamily.?) break;
        }

        if (graphicsFamily == null or presentFamily == null) continue;

        var extensionCount: u32 = 0;
        try vk.checkResult(c.vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, null));

        const availableExtensions = try allocator.alloc(c.VkExtensionProperties, extensionCount);
        try vk.checkResult(c.vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, availableExtensions.ptr));

        var hasSwapchain = false;
        for (availableExtensions) |ext| {
            const name = @as([*:0]const u8, @ptrCast(&ext.extensionName));
            if (std.mem.eql(u8, std.mem.span(name), c.VK_KHR_SWAPCHAIN_EXTENSION_NAME)) {
                hasSwapchain = true;
                break;
            }
        }

        if (!hasSwapchain) continue;

        var formatCount: u32 = 0;
        try vk.checkResult(c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, null));
        var presentModeCount: u32 = 0;
        try vk.checkResult(c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, null));

        if (formatCount == 0 or presentModeCount == 0) continue;

        physicalDeviceIndex = deviceIndex;
        physicalDevice = device;
        break;
    }

    if (physicalDeviceIndex == null) return null;
    std.log.info("Chosen device: {?}", .{physicalDeviceIndex});

    if (presentFamily.? != graphicsFamily.?) {
        std.log.err("presentFamily {} is not the same as graphicsFamily {}, giving up", .{ presentFamily.?, graphicsFamily.? });
        return null;
    }

    return PysicalDevicePick{
        .device = physicalDevice,
        .queue = @intCast(presentFamily.?),
    };
}
