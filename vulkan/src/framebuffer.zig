const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;
const sc = @import("swapchain.zig");

pub fn createFramebuffer(
    logicalDevice: c.VkDevice,
    attachments: []const c.VkImageView,
    renderPass: c.VkRenderPass,
    width: u32,
    height: u32,
) !c.VkFramebuffer {
    var framebuffer: c.VkFramebuffer = undefined;

    var framebufferInfo = c.VkFramebufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .renderPass = renderPass,
        .attachmentCount = @intCast(attachments.len),
        .pAttachments = attachments.ptr,
        .width = width,
        .height = height,
        .layers = 1,
    };

    try vk.checkResult(c.vkCreateFramebuffer(
        logicalDevice,
        &framebufferInfo,
        null,
        &framebuffer,
    ));

    return framebuffer;
}

pub fn createFramebuffers(
    allocator: std.mem.Allocator,
    logicalDevice: c.VkDevice,
    imageViews: []sc.SwapchainImage,
    depthImageViews: []c.VkImageView,
    renderPass: c.VkRenderPass,
    width: u32,
    height: u32,
) ![]c.VkFramebuffer {
    const framebuffers = try allocator.alloc(c.VkFramebuffer, imageViews.len);

    for (imageViews, 0..) |view, i| {
        const attachments = [_]c.VkImageView{
            view.imageView,
            depthImageViews[i],
        };

        framebuffers[i] = try createFramebuffer(logicalDevice, attachments[0..], renderPass, width, height);
    }

    return framebuffers;
}
