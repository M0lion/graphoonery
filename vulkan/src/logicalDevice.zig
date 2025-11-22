const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;

pub fn createLogicalDevice(physicalDevice: c.VkPhysicalDevice, queueFamily: u32) !c.VkDevice {
    const queuePriority: f32 = 1.0;
    const queueCreateInfo = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = @intCast(queueFamily),
        .queueCount = 1,
        .pQueuePriorities = &queuePriority,
    };
    const deviceExtensions = [_][*:0]const u8{
        c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
    };
    const createInfo = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queueCreateInfo,
        .queueCreateInfoCount = 1,
        .pEnabledFeatures = null,
        .enabledExtensionCount = deviceExtensions.len,
        .ppEnabledExtensionNames = &deviceExtensions,
    };
    var logicalDevice: c.VkDevice = null;
    try vk.checkResult(c.vkCreateDevice(physicalDevice, &createInfo, null, &logicalDevice));
    return logicalDevice;
}
