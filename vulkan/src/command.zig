const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;

pub fn createCommandPool(
    logicalDevice: c.VkDevice,
    queueFamily: u32,
) !c.VkCommandPool {
    var poolInfo = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .pNext = null,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = @intCast(queueFamily),
    };

    var commandPool: c.VkCommandPool = undefined;
    try vk.checkResult(c.vkCreateCommandPool(logicalDevice, &poolInfo, null, &commandPool));

    return commandPool;
}

pub fn destroyCommandPool(logicalDevice: c.VkDevice, commandPool: c.VkCommandPool) void {
    c.vkDestroyCommandPool(logicalDevice, commandPool, null);
}

pub fn allocateCommandBuffer(
    logicalDevice: c.VkDevice,
    commandPool: c.VkCommandPool,
) !c.VkCommandBuffer {
    var allocInfo = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = commandPool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var commandBuffer: c.VkCommandBuffer = undefined;
    try vk.checkResult(c.vkAllocateCommandBuffers(logicalDevice, &allocInfo, &commandBuffer));

    return commandBuffer;
}

pub fn freeCommandBuffer(
    device: c.VkDevice,
    commandPool: c.VkCommandPool,
    buffer: c.VkCommandBuffer,
) void {
    c.vkFreeCommandBuffers(device, commandPool, 1, &buffer);
}
