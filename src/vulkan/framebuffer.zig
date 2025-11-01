const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;

pub fn createFramebuffers(
    allocator: std.mem.Allocator,
    logicalDevice: c.VkDevice,
    imageViews: []c.VkImageView,
    renderPass: c.VkRenderPass,
    width: u32,
    height: u32,
) ![]c.VkFramebuffer {
    const framebuffers = try allocator.alloc(c.VkFramebuffer, imageViews.len);

    for (imageViews, 0..) |view, i| {
        const attachments = [_]c.VkImageView{view};

        var framebufferInfo = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .renderPass = renderPass,
            .attachmentCount = 1,
            .pAttachments = &attachments,
            .width = width,
            .height = height,
            .layers = 1,
        };

        try vk.checkResult(c.vkCreateFramebuffer(
            logicalDevice,
            &framebufferInfo,
            null,
            &framebuffers[i],
        ));
    }

    return framebuffers;
}
