const vulkan = @import("vulkan");
const vk = vulkan.vk;
const c = vk.c;
const pipe = vulkan.pipeline;
const VulkanContext = vulkan.context.VulkanContext;
const shaders = @import("shaders");
const descriptor = vulkan.descriptor;
const buffer = vulkan.buffer;
const Mat4 = @import("math/mat4.zig").Mat4;

pub const RoundedCornerPipeline = struct {
    pub const PushConstants = extern struct {
        resolution: [2]f32, // offset  0
        center: [2]f32, // offset  8
        half_size: [2]f32, // offset 16
        radius: f32, // offset 24
        border: f32, // offset 28
        fill: [4]f32, // offset 32
        border_color: [4]f32, // offset 48
    }; // total   64 bytes

    pipeline: c.VkPipeline,
    layout: c.VkPipelineLayout,
    context: VulkanContext,
    fragmentShaderModule: c.VkShaderModule,
    vertexShaderModule: c.VkShaderModule,

    pub fn init(vulkanContext: VulkanContext) !RoundedCornerPipeline {
        const logicalDevice = vulkanContext.logicalDevice;

        var vertCreateInfo = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = shaders.roundedCornerRect_vert_spv.len,
            .pCode = @ptrCast(@alignCast(shaders.roundedCornerRect_vert_spv.ptr)),
        };

        var vertShaderModule: c.VkShaderModule = undefined;
        try vk.checkResult(c.vkCreateShaderModule(logicalDevice, &vertCreateInfo, null, &vertShaderModule));

        var fragCreateInfo = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = shaders.roundedCornerRect_frag_spv.len,
            .pCode = @ptrCast(@alignCast(shaders.roundedCornerRect_frag_spv.ptr)),
        };

        var fragShaderModule: c.VkShaderModule = undefined;
        try vk.checkResult(c.vkCreateShaderModule(logicalDevice, &fragCreateInfo, null, &fragShaderModule));

        const pipelineResult = try pipe.createGraphicsPipeline(.{
            .logicalDevice = logicalDevice,
            .vertShaderModule = vertShaderModule,
            .fragShaderModule = fragShaderModule,
            .width = vulkanContext.width,
            .height = vulkanContext.height,
            .renderPass = vulkanContext.renderPass,
            .topology = pipe.Topology.TriangleStrip,
        });

        return RoundedCornerPipeline{
            .pipeline = pipelineResult.pipeline,
            .layout = pipelineResult.layout,
            .context = vulkanContext,
            .fragmentShaderModule = fragShaderModule,
            .vertexShaderModule = vertShaderModule,
        };
    }

    pub fn deinit(self: *RoundedCornerPipeline) void {
        const logicalDevice = self.context.logicalDevice;

        c.vkDestroyShaderModule(logicalDevice, self.fragmentShaderModule, null);
        c.vkDestroyShaderModule(logicalDevice, self.vertexShaderModule, null);
        pipe.destroyPipeline(logicalDevice, self.pipeline);
        pipe.destroyPipelineLayout(logicalDevice, self.layout);
    }

    pub fn draw(
        self: *RoundedCornerPipeline,
        commandBuffer: c.VkCommandBuffer,
        rect: PushConstants,
    ) !void {
        c.vkCmdBindPipeline(commandBuffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);
        c.vkCmdPushConstants(commandBuffer, self.layout, c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(PushConstants), &rect);
        c.vkCmdDraw(commandBuffer, 4, 1, 0, 0); // 4 vertices, 1 instance
    }
};
