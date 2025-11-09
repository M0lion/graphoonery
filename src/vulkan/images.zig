const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;
const mem = @import("memory.zig");

pub const ImageResult = struct {
    image: c.VkImage,
    memory: c.VkDeviceMemory,
    imageView: c.VkImageView,
};

pub fn createDepthImages(
    allocator: std.mem.Allocator,
    logicalDevice: c.VkDevice,
    physicalDevice: c.VkPhysicalDevice,
    width: u32,
    height: u32,
    count: usize,
) ![]ImageResult {
    var images = try allocator.alloc(ImageResult, count);
    var i: usize = 0;
    while (i < count) {
        images[i] = try createDepthImage(
            logicalDevice,
            physicalDevice,
            width,
            height,
        );
        i += 1;
    }
    return images;
}

pub fn freeImages(logicalDevice: c.VkDevice, images: []ImageResult) void {
    for (images) |imageResult| {
        c.vkDestroyImageView(logicalDevice, imageResult.imageView, null);
        c.vkFreeMemory(logicalDevice, imageResult.memory, null);
        c.vkDestroyImage(logicalDevice, imageResult.image, null);
    }
}

pub fn createDepthImage(
    logicalDevice: c.VkDevice,
    physicalDevice: c.VkPhysicalDevice,
    width: u32,
    height: u32,
) !ImageResult {
    const format = c.VK_FORMAT_D32_SFLOAT;
    const imageCreateInfo = c.VkImageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .extent = .{
            .width = width,
            .height = height,
            .depth = 1,
        },
        .mipLevels = 1,
        .arrayLayers = 1,
        .format = format,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .usage = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    };

    var image: c.VkImage = undefined;
    try vk.checkResult(c.vkCreateImage(logicalDevice, &imageCreateInfo, null, &image));

    const memory = try mem.allocateImageMemory(
        logicalDevice,
        physicalDevice,
        image,
    );

    const viewInfo = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    var imageView: c.VkImageView = undefined;
    try vk.checkResult(c.vkCreateImageView(
        logicalDevice,
        &viewInfo,
        null,
        &imageView,
    ));

    return ImageResult{
        .image = image,
        .memory = memory,
        .imageView = imageView,
    };
}
