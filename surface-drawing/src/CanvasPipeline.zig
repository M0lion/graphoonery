const std = @import("std");
const vulkan = @import("vulkan");
const vk = vulkan.vk;
const c = vk.c;
const pipe = vulkan.pipeline;
const VulkanContext = vulkan.context.VulkanContext;
const shaders = @import("shaders");
const descriptor = vulkan.descriptor;
const buffer = vulkan.buffer;
const math = @import("math");
const Mat4 = math.Mat4;

pub const CanvasPipeline = struct {
    pub const PushConstants = extern struct {
        resolution: math.Vec2, // offset  0
        center: math.Vec2, // offset  8
        fill: math.Vec4, // offset 32
        radius: f32, // offset 24
    }; // total   64 bytes

    pipeline: c.VkPipeline,
    layout: c.VkPipelineLayout,
    context: VulkanContext,
    fragmentShaderModule: c.VkShaderModule,
    vertexShaderModule: c.VkShaderModule,
    renderPass: c.VkRenderPass,
    sampler: c.VkSampler,
    descriptorSetLayout: c.VkDescriptorSetLayout,

    pub const Config = struct {
        renderPass: c.VkRenderPass,
    };

    pub fn init(vulkanContext: VulkanContext, config: Config, allocator: std.mem.Allocator) !CanvasPipeline {
        const logicalDevice = vulkanContext.logicalDevice;

        var vertCreateInfo = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = shaders.canvas_vert_spv.len,
            .pCode = @ptrCast(@alignCast(shaders.canvas_vert_spv.ptr)),
        };

        var vertShaderModule: c.VkShaderModule = undefined;
        try vk.checkResult(c.vkCreateShaderModule(logicalDevice, &vertCreateInfo, null, &vertShaderModule));

        var fragCreateInfo = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = shaders.canvas_frag_spv.len,
            .pCode = @ptrCast(@alignCast(shaders.canvas_frag_spv.ptr)),
        };

        var fragShaderModule: c.VkShaderModule = undefined;
        try vk.checkResult(c.vkCreateShaderModule(logicalDevice, &fragCreateInfo, null, &fragShaderModule));

        const descriptorSetLayouts = [_]descriptor.DescriptorSetLayoutBinding{
            descriptor.DescriptorSetLayoutBinding{
                .descriptorType = descriptor.DescriptorType.CombinedImageSampler,
                .shaderStage = descriptor.ShaderStage.Fragment,
            },
        };

        const layout = try descriptor.createDescriptorSetLayout(allocator, vulkanContext.logicalDevice, &descriptorSetLayouts);
        const layouts = [_]c.VkDescriptorSetLayout{layout};

        const pipelineResult = try pipe.createGraphicsPipeline(.{
            .logicalDevice = logicalDevice,
            .vertShaderModule = vertShaderModule,
            .fragShaderModule = fragShaderModule,
            .renderPass = config.renderPass,
            .topology = pipe.Topology.TriangleStrip,
            .descriptorSetLayouts = &layouts,
        });

        const sampler = try vulkan.sampler.Sampler.init(vulkanContext);

        return CanvasPipeline{
            .pipeline = pipelineResult.pipeline,
            .layout = pipelineResult.layout,
            .context = vulkanContext,
            .fragmentShaderModule = fragShaderModule,
            .vertexShaderModule = vertShaderModule,
            .renderPass = config.renderPass,
            .sampler = sampler.sampler,
            .descriptorSetLayout = layout,
        };
    }

    pub fn deinit(self: *CanvasPipeline) void {
        const logicalDevice = self.context.logicalDevice;

        c.vkDestroyShaderModule(logicalDevice, self.fragmentShaderModule, null);
        c.vkDestroyShaderModule(logicalDevice, self.vertexShaderModule, null);
        pipe.destroyPipeline(logicalDevice, self.pipeline);
        pipe.destroyPipelineLayout(logicalDevice, self.layout);
    }

    pub fn draw(
        self: *CanvasPipeline,
        commandBuffer: c.VkCommandBuffer,
        descriptorSet: c.VkDescriptorSet,
    ) void {
        c.vkCmdBindPipeline(commandBuffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);
        c.vkCmdBindDescriptorSets(
            commandBuffer,
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.layout, // must be the pipeline's own layout
            0, // firstSet — matches set = 0
            1,
            &descriptorSet,
            0,
            null,
        );
        c.vkCmdDraw(commandBuffer, 4, 1, 0, 0);
    }

    pub fn createDescriptorSet(
        self: *CanvasPipeline,
        image: vulkan.images.ImageResult,
    ) !c.VkDescriptorSet {
        const set = try descriptor.allocateDescriptorSet(
            self.context.logicalDevice,
            self.context.descriptorPool,
            self.descriptorSetLayout,
        );
        descriptor.updateDescriptorSet(self.context.logicalDevice, set, 0, .{
            .CombinedImageSampler = .{
                .imageView = image.imageView,
                .sampler = self.sampler,
            },
        });
        return set;
    }
};
