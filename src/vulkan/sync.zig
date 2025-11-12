const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;

pub const SyncObjects = struct {
    imageAvailableSemaphore: c.VkSemaphore,
    inFlightFence: c.VkFence,
};

pub fn createSemaphore(logicalDevice: c.VkDevice) !c.VkSemaphore {
    var semaphoreInfo = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
    };

    var semaphore: c.VkSemaphore = undefined;
    try vk.checkResult(c.vkCreateSemaphore(
        logicalDevice,
        &semaphoreInfo,
        null,
        &semaphore,
    ));
    return semaphore;
}

pub fn createSyncObjects(logicalDevice: c.VkDevice) !SyncObjects {
    var imageAvailableSemaphore: c.VkSemaphore = undefined;

    var semaphoreInfo = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
    };

    try vk.checkResult(c.vkCreateSemaphore(
        logicalDevice,
        &semaphoreInfo,
        null,
        &imageAvailableSemaphore,
    ));

    var fenceInfo = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .pNext = null,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    var inFlightFence: c.VkFence = undefined;
    try vk.checkResult(c.vkCreateFence(
        logicalDevice,
        &fenceInfo,
        null,
        &inFlightFence,
    ));

    return SyncObjects{
        .imageAvailableSemaphore = imageAvailableSemaphore,
        .inFlightFence = inFlightFence,
    };
}

pub fn destroySemaphore(logicalDevice: c.VkDevice, semaphore: c.VkSemaphore) void {
    c.vkDestroySemaphore(logicalDevice, semaphore, null);
}

pub fn destroyFence(logicalDevice: c.VkDevice, fence: c.VkFence) void {
    c.vkDestroyFence(logicalDevice, fence, null);
}
