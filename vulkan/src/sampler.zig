const vk = @import("vk.zig");
const c = vk.c;
const VulkanContext = @import("vulkanContext.zig").VulkanContext;

pub const Sampler = struct {
    sampler: c.VkSampler,

    pub fn init(context: VulkanContext) !Sampler {
        const samplerInfo = c.VkSamplerCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = c.VK_FILTER_LINEAR,
            .minFilter = c.VK_FILTER_LINEAR,
            .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_NEAREST,
            .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .mipLodBias = 0.0,
            .anisotropyEnable = c.VK_FALSE,
            .maxAnisotropy = 1.0,
            .compareEnable = c.VK_FALSE,
            .compareOp = c.VK_COMPARE_OP_ALWAYS,
            .minLod = 0.0,
            .maxLod = 0.0,
            .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
            .unnormalizedCoordinates = c.VK_FALSE,
        };

        var sampler: c.VkSampler = undefined;
        try vk.checkResult(c.vkCreateSampler(context.logicalDevice, &samplerInfo, null, &sampler));

        return .{
            .sampler = sampler,
        };
    }

    pub fn deinit(self: *Sampler, context: VulkanContext) void {
        c.vkDestroySampler(context.logicalDevice, self.sampler, null);
    }
};
