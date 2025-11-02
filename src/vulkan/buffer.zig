const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;

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

    var memRequirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(logicalDevice, buffer, &memRequirements);

    const memoryTypeIndex = try findMemoryType(
        physicalDevice,
        memRequirements.memoryTypeBits,
        properties,
    );

    var allocInfo = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = null,
        .allocationSize = memRequirements.size,
        .memoryTypeIndex = memoryTypeIndex,
    };

    var bufferMemory: c.VkDeviceMemory = undefined;
    try vk.checkResult(c.vkAllocateMemory(logicalDevice, &allocInfo, null, &bufferMemory));

    try vk.checkResult(c.vkBindBufferMemory(logicalDevice, buffer, bufferMemory, 0));

    return .{ .buffer = buffer, .memory = bufferMemory };
}

pub fn destroyBuffer(logicalDevice: c.VkDevice, buffer: c.VkBuffer) void {
    c.vkDestroyBuffer(logicalDevice, buffer, null);
}

pub fn freeMemory(logicalDevice: c.VkDevice, memory: c.VkDeviceMemory) void {
    c.vkFreeMemory(logicalDevice, memory, null);
}

fn findMemoryType(
    physicalDevice: c.VkPhysicalDevice,
    typeFilter: u32,
    properties: c.VkMemoryPropertyFlags,
) !u32 {
    var memProperties: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties);

    var i: u32 = 0;
    while (i < memProperties.memoryTypeCount) : (i += 1) {
        if ((typeFilter & (@as(u32, 1) << @intCast(i))) != 0 and
            (memProperties.memoryTypes[i].propertyFlags & properties) == properties)
        {
            return i;
        }
    }

    return error.NoSuitableMemoryType;
}
