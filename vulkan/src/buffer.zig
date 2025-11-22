const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;
const mem = @import("memory.zig");

pub fn createBuffer(
    physicalDevice: c.VkPhysicalDevice,
    logicalDevice: c.VkDevice,
    size: c.VkDeviceSize,
    usage: c.VkBufferUsageFlags,
    properties: c.VkMemoryPropertyFlags,
) !struct { buffer: c.VkBuffer, memory: c.VkDeviceMemory } {
    var bufferInfo = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .size = size,
        .usage = usage,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
    };

    var buffer: c.VkBuffer = undefined;
    try vk.checkResult(c.vkCreateBuffer(logicalDevice, &bufferInfo, null, &buffer));

    const memory = try mem.allocateBufferMemory(
        logicalDevice,
        physicalDevice,
        buffer,
        properties,
    );

    return .{ .buffer = buffer, .memory = memory };
}

pub fn destroyBuffer(logicalDevice: c.VkDevice, buffer: c.VkBuffer) void {
    c.vkDestroyBuffer(logicalDevice, buffer, null);
}

pub fn freeMemory(logicalDevice: c.VkDevice, memory: c.VkDeviceMemory) void {
    c.vkFreeMemory(logicalDevice, memory, null);
}
