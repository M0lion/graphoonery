const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;
const EnumFromC = @import("enumFromC.zig").EnumFromC;
const i = @import("images.zig");
const ImageLayout = i.ImageLayout;

pub const AttachmentLoadOp = enum(c_uint) {
    Clear = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
    Load = c.VK_ATTACHMENT_LOAD_OP_LOAD,
    DontCare = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
};

pub const AttachmentStoreOp = enum(c_uint) {
    Store = c.VK_ATTACHMENT_STORE_OP_STORE,
    DontCare = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
};

pub const SampleCount = enum(c_uint) {
    Count_1 = c.VK_SAMPLE_COUNT_1_BIT,
};

pub const Attachment = struct {
    loadOp: AttachmentLoadOp,
    storeOp: AttachmentStoreOp,
    stenciilLoadOp: AttachmentLoadOp,
    stencilStoreOp: AttachmentStoreOp,
    initialLayout: ImageLayout,
    finalLayout: ImageLayout,
    sampleCount: SampleCount,
    format: c.VkFormat,

    pub fn getVkAttachmentDescription(self: *const Attachment) c.VkAttachmentDescription {
        return c.VkAttachmentDescription{
            .flags = 0,
            .format = self.format,
            .samples = @intFromEnum(self.sampleCount),
            .loadOp = @intFromEnum(self.loadOp),
            .storeOp = @intFromEnum(self.storeOp),
            .stencilLoadOp = @intFromEnum(self.stenciilLoadOp),
            .stencilStoreOp = @intFromEnum(self.stencilStoreOp),
            .initialLayout = @intFromEnum(self.initialLayout),
            .finalLayout = @intFromEnum(self.finalLayout),
        };
    }
};

pub const RenderPassConfig = struct {
    colorAttachment: Attachment,
    depthAttachment: ?Attachment = null,
};

pub fn createRenderPass(
    logicalDevice: c.VkDevice,
    config: RenderPassConfig,
) !c.VkRenderPass {
    // Attachment 0 is always color; attachment 1 is depth when configured.
    // Everything Vulkan reads must outlive the vkCreateRenderPass call, so
    // these are plain function-scope locals rather than slices of temporaries.
    var attachments: [2]c.VkAttachmentDescription = undefined;
    attachments[0] = config.colorAttachment.getVkAttachmentDescription();

    var colorAttachmentRef = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    var depthAttachmentRef = c.VkAttachmentReference{
        .attachment = 1, // index 1 (color is 0)
        .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    };

    var attachmentCount: u32 = 1;
    if (config.depthAttachment) |depthAttachmentConfig| {
        attachments[1] = depthAttachmentConfig.getVkAttachmentDescription();
        attachmentCount = 2;
    }

    var subpass = c.VkSubpassDescription{
        .flags = 0,
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &colorAttachmentRef,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .pResolveAttachments = null,
        .pDepthStencilAttachment = if (config.depthAttachment != null) &depthAttachmentRef else null,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    };

    var createRenderPassInfo = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = attachmentCount,
        .pAttachments = &attachments,
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
