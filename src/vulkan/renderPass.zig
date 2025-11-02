const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;

pub fn createRenderPass(
    logicalDevice: c.VkDevice,
    format: c.VkFormat,
) !c.VkRenderPass {
    var colorAttachment = c.VkAttachmentDescription{
        .flags = 0,
        .format = format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    var colorAttachmentRef = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    var subpass = c.VkSubpassDescription{
        .flags = 0,
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &colorAttachmentRef,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .pResolveAttachments = null,
        .pDepthStencilAttachment = null,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    };

    var createRenderPassInfo = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = 1,
        .pAttachments = &colorAttachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 0,
        .pDependencies = null,
    };

    var renderPass: c.VkRenderPass = undefined;
    try vk.checkResult(c.vkCreateRenderPass(
        logicalDevice,
        &createRenderPassInfo,
        null,
        &renderPass,
    ));

    return renderPass;
}

pub fn destroyRenderPass(logicalDevice: c.VkDevice, renderPass: c.VkRenderPass) void {
    c.vkDestroyRenderPass(logicalDevice, renderPass, null);
}
