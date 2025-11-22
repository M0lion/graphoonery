const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;

pub fn createImageView(
    logicalDevice: c.VkDevice,
    image: c.VkImage,
    format: c.VkFormat,
) !c.VkImageView {
    var imageViewCreateInfo = c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .image = image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .components = .{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    var imageView: c.VkImageView = undefined;
    try vk.checkResult(c.vkCreateImageView(
        logicalDevice,
        &imageViewCreateInfo,
        null,
        &imageView,
    ));

    return imageView;
}

pub fn createImageViews(
    allocator: std.mem.Allocator,
    logicalDevice: c.VkDevice,
    images: []c.VkImage,
    format: c.VkFormat,
) ![]c.VkImageView {
    const imageViews = try allocator.alloc(c.VkImageView, images.len);

    for (images, 0..) |image, i| {
        var imageViewCreateInfo = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = format,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        try vk.checkResult(c.vkCreateImageView(
            logicalDevice,
            &imageViewCreateInfo,
            null,
            &imageViews[i],
        ));
    }

    return imageViews;
}
