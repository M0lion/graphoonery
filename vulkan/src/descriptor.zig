const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;
const img = @import("images.zig");
const ImageLayout = img.ImageLayout;

pub const DescriptorType = enum(c_uint) {
    UniformBuffer = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    CombinedImageSampler = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
};
pub const ShaderStage = enum(u32) {
    Vertex = c.VK_SHADER_STAGE_VERTEX_BIT,
    Fragment = c.VK_SHADER_STAGE_FRAGMENT_BIT,
};
pub const DescriptorSetLayoutBinding = struct {
    descriptorType: DescriptorType,
    shaderStage: ShaderStage,
};

pub fn createDescriptorSetLayout(allocator: std.mem.Allocator, logicalDevice: c.VkDevice, bindings: []const DescriptorSetLayoutBinding) !c.VkDescriptorSetLayout {
    var uboLayoutBindings = try allocator.alloc(c.VkDescriptorSetLayoutBinding, bindings.len);
    for (bindings, 0..) |binding, i| {
        uboLayoutBindings[i] = c.VkDescriptorSetLayoutBinding{
            .binding = @intCast(i),
            .descriptorType = @intFromEnum(binding.descriptorType),
            .descriptorCount = 1,
            .stageFlags = @intFromEnum(binding.shaderStage),
            .pImmutableSamplers = null,
        };
    }

    var layoutInfo = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .bindingCount = @intCast(uboLayoutBindings.len),
        .pBindings = uboLayoutBindings.ptr,
    };

    var descriptorSetLayout: c.VkDescriptorSetLayout = undefined;
    try vk.checkResult(c.vkCreateDescriptorSetLayout(
        logicalDevice,
        &layoutInfo,
        null,
        &descriptorSetLayout,
    ));

    return descriptorSetLayout;
}

pub fn destroyDescriptorSetLayout(
    logicalDevice: c.VkDevice,
    descriptorSetLayout: c.VkDescriptorSetLayout,
) void {
    c.vkDestroyDescriptorSetLayout(logicalDevice, descriptorSetLayout, null);
}

pub fn createDescriptorPool(logicalDevice: c.VkDevice) !c.VkDescriptorPool {
    var sizes = [_]c.VkDescriptorPoolSize{
        c.VkDescriptorPoolSize{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 10,
        },
        c.VkDescriptorPoolSize{
            .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 10,
        },
    };

    var poolInfo = c.VkDescriptorPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .pNext = null,
        .flags = c.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        .poolSizeCount = sizes.len,
        .pPoolSizes = &sizes,
        .maxSets = 10,
    };

    var descriptorPool: c.VkDescriptorPool = undefined;
    try vk.checkResult(c.vkCreateDescriptorPool(
        logicalDevice,
        &poolInfo,
        null,
        &descriptorPool,
    ));

    return descriptorPool;
}

pub fn destroyDescriptorPool(
    logicalDevice: c.VkDevice,
    descriptorPool: c.VkDescriptorPool,
) void {
    c.vkDestroyDescriptorPool(logicalDevice, descriptorPool, null);
}

pub fn allocateDescriptorSet(
    logicalDevice: c.VkDevice,
    descriptorPool: c.VkDescriptorPool,
    descriptorSetLayout: c.VkDescriptorSetLayout,
) !c.VkDescriptorSet {
    var allocInfo = c.VkDescriptorSetAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = descriptorPool,
        .descriptorSetCount = 1,
        .pSetLayouts = &descriptorSetLayout,
    };

    var descriptorSet: c.VkDescriptorSet = undefined;
    try vk.checkResult(c.vkAllocateDescriptorSets(
        logicalDevice,
        &allocInfo,
        &descriptorSet,
    ));

    return descriptorSet;
}

pub const DescriptorData = union(DescriptorType) {
    UniformBuffer: struct {
        buffer: c.VkBuffer,
        size: c.VkDeviceSize,
    },
    CombinedImageSampler: struct {
        imageView: c.VkImageView,
        sampler: c.VkSampler,
        layout: ImageLayout = .ShaderReadOnlyOptimal,
    },
};

pub fn updateDescriptorSet(
    logicalDevice: c.VkDevice,
    descriptorSet: c.VkDescriptorSet,
    binding: u32,
    data: DescriptorData,
) void {
    // Both info structs are function-scope so they outlive the
    // vkUpdateDescriptorSets call that points at them.
    var bufferInfo: c.VkDescriptorBufferInfo = undefined;
    var imageInfo: c.VkDescriptorImageInfo = undefined;

    var descriptorWrite = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .pNext = null,
        .dstSet = descriptorSet,
        .dstBinding = binding,
        .dstArrayElement = 0,
        .descriptorType = @intFromEnum(std.meta.activeTag(data)),
        .descriptorCount = 1,
        .pBufferInfo = null,
        .pImageInfo = null,
        .pTexelBufferView = null,
    };

    switch (data) {
        .UniformBuffer => |ub| {
            bufferInfo = .{
                .buffer = ub.buffer,
                .offset = 0,
                .range = ub.size,
            };
            descriptorWrite.pBufferInfo = &bufferInfo;
        },
        .CombinedImageSampler => |cis| {
            imageInfo = .{
                .sampler = cis.sampler,
                .imageView = cis.imageView,
                .imageLayout = @intFromEnum(cis.layout),
            };
            descriptorWrite.pImageInfo = &imageInfo;
        },
    }

    c.vkUpdateDescriptorSets(logicalDevice, 1, &descriptorWrite, 0, null);
}

pub fn destroyDescriptorSet(logicalDevice: c.VkDevice, descriptorPool: c.VkDescriptorPool, descriptorSet: *c.VkDescriptorSet) !void {
    try vk.checkResult(c.vkFreeDescriptorSets(logicalDevice, descriptorPool, 1, descriptorSet));
}
