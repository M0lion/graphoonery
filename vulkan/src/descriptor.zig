const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;

pub const DescriptorType = enum(c_uint) {
    UniformBuffer = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
};
pub const ShaderStage = enum(u32) {
    Vertex = c.VK_SHADER_STAGE_VERTEX_BIT,
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
    var poolSize = c.VkDescriptorPoolSize{
        .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 10,
    };

    var poolInfo = c.VkDescriptorPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .pNext = null,
        .flags = c.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        .poolSizeCount = 1,
        .pPoolSizes = &poolSize,
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

pub fn updateDescriptorSet(
    logicalDevice: c.VkDevice,
    descriptorSet: c.VkDescriptorSet,
    buffer: c.VkBuffer,
    bufferSize: c.VkDeviceSize,
) void {
    var bufferInfo = c.VkDescriptorBufferInfo{
        .buffer = buffer,
        .offset = 0,
        .range = bufferSize,
    };

    var descriptorWrite = c.VkWriteDescriptorSet{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .pNext = null,
        .dstSet = descriptorSet,
        .dstBinding = 0,
        .dstArrayElement = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .pBufferInfo = &bufferInfo,
        .pImageInfo = null,
        .pTexelBufferView = null,
    };

    c.vkUpdateDescriptorSets(logicalDevice, 1, &descriptorWrite, 0, null);
}

pub fn destroyDescriptorSet(logicalDevice: c.VkDevice, descriptorPool: c.VkDescriptorPool, descriptorSet: *c.VkDescriptorSet) !void {
    try vk.checkResult(c.vkFreeDescriptorSets(logicalDevice, descriptorPool, 1, descriptorSet));
}
