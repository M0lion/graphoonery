const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;

pub fn allocateBufferMemory(
    logicalDevice: c.VkDevice,
    physicalDevice: c.VkPhysicalDevice,
    buffer: c.VkBuffer,
    properties: c.VkMemoryPropertyFlags,
) !c.VkDeviceMemory {
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
    return bufferMemory;
}

pub fn allocateImageMemory(
    logicalDevice: c.VkDevice,
    physicalDevice: c.VkPhysicalDevice,
    image: c.VkImage,
) !c.VkDeviceMemory {
    var requirements: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(
        logicalDevice,
        image,
        &requirements,
    );
    const memoryTypeIndex = try findMemoryType(
        physicalDevice,
        requirements.memoryTypeBits,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    );

    const alloc_info = c.VkMemoryAllocateInfo{
        .allocationSize = requirements.size,
        .memoryTypeIndex = memoryTypeIndex,
    };

    var memory: c.VkDeviceMemory = undefined;
    try vk.checkResult(c.vkAllocateMemory(
        logicalDevice,
        &alloc_info,
        null,
        &memory,
    ));
    try vk.checkResult(c.vkBindImageMemory(logicalDevice, image, memory, 0));
    return memory;
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

pub fn freeMemory(logicalDevice: c.VkDevice, memory: c.VkDeviceMemory) void {
    c.vkFreeMemory(logicalDevice, memory, null);
}
