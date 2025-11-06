const vk = @import("vulkan/vk.zig");
const c = vk.c;
const pipe = @import("vulkan/pipeline.zig");
const VulkanContext = @import("vulkan/vulkanContext.zig").VulkanContext;
const shaders = @import("shaders");
const descriptor = @import("vulkan/descriptor.zig");
const buffer = @import("vulkan/buffer.zig");
const Mat4 = @import("math/mat4.zig").Mat4;

pub const ColoredVertexPipeline = struct {
    pub const Vertex = struct {
        position: [3]f32,
        color: [4]f32,
        normal: [4]f32,
    };

    pipeline: c.VkPipeline,
    layout: c.VkPipelineLayout,
    descriptorSetLayout: c.VkDescriptorSetLayout,
    descriptorPool: c.VkDescriptorPool,
    context: VulkanContext,
    fragmentShaderModule: c.VkShaderModule,
    vertexShaderModule: c.VkShaderModule,

    pub fn init(vulkanContext: VulkanContext) !ColoredVertexPipeline {
        const logicalDevice = vulkanContext.logicalDevice;

        const descriptorSetLayout = try descriptor.createDescriptorSetLayout(logicalDevice);

        const descriptorPool = try descriptor.createDescriptorPool(logicalDevice);

        var vertCreateInfo = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = shaders.vertex_vert_spv.len,
            .pCode = @ptrCast(@alignCast(shaders.vertex_vert_spv.ptr)),
        };

        var vertShaderModule: c.VkShaderModule = undefined;
        try vk.checkResult(c.vkCreateShaderModule(logicalDevice, &vertCreateInfo, null, &vertShaderModule));

        var fragCreateInfo = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .codeSize = shaders.fragment_frag_spv.len,
            .pCode = @ptrCast(@alignCast(shaders.fragment_frag_spv.ptr)),
        };

        var fragShaderModule: c.VkShaderModule = undefined;
        try vk.checkResult(c.vkCreateShaderModule(logicalDevice, &fragCreateInfo, null, &fragShaderModule));

        var bindingDescriptions = [_]c.VkVertexInputBindingDescription{
            .{
                .binding = 0,
                .stride = @sizeOf(Vertex),
                .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
            },
        };

        var attributeDescriptions = [_]c.VkVertexInputAttributeDescription{
            .{ // Position
                .binding = 0,
                .location = 0,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "position"),
            },
            .{ // Color
                .binding = 0,
                .location = 1,
                .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
                .offset = @offsetOf(Vertex, "color"),
            },
            .{ // Normal
                .binding = 0,
                .location = 2,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = @offsetOf(Vertex, "normal"),
            },
        };

        const pipelineResult = try pipe.createGraphicsPipeline(.{
            .logicalDevice = logicalDevice,
            .vertShaderModule = vertShaderModule,
            .fragShaderModule = fragShaderModule,
            .width = vulkanContext.width,
            .height = vulkanContext.height,
            .renderPass = vulkanContext.renderPass,
            .descriptorSetLayout = descriptorSetLayout,
            .vertexBindingDescriptions = &bindingDescriptions,
            .vertexAttributeDescriptions = &attributeDescriptions,
        });

        return ColoredVertexPipeline{
            .pipeline = pipelineResult.pipeline,
            .layout = pipelineResult.layout,
            .descriptorSetLayout = descriptorSetLayout,
            .descriptorPool = descriptorPool,
            .context = vulkanContext,
            .fragmentShaderModule = fragShaderModule,
            .vertexShaderModule = vertShaderModule,
        };
    }

    pub fn deinit(self: *ColoredVertexPipeline) void {
        const logicalDevice = self.context.logicalDevice;

        c.vkDestroyShaderModule(logicalDevice, self.fragmentShaderModule, null);
        c.vkDestroyShaderModule(logicalDevice, self.vertexShaderModule, null);
        pipe.destroyPipeline(logicalDevice, self.pipeline);
        pipe.destroyPipelineLayout(logicalDevice, self.layout);
        descriptor.destroyDescriptorPool(logicalDevice, self.descriptorPool);
        descriptor.destroyDescriptorSetLayout(logicalDevice, self.descriptorSetLayout);
    }

    pub fn draw(
        self: *ColoredVertexPipeline,
        commandBuffer: c.VkCommandBuffer,
        transform: *const TransformUBO,
        mesh: *const Mesh,
    ) !void {
        c.vkCmdBindPipeline(commandBuffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipeline);
        c.vkCmdBindDescriptorSets(
            commandBuffer,
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            self.layout,
            0,
            1,
            &transform.descriptorSet,
            0,
            null,
        );
        const offset: u64 = 0;
        c.vkCmdBindVertexBuffers(commandBuffer, 0, 1, &mesh.buffer, &offset);

        c.vkCmdDraw(commandBuffer, mesh.vertices, 1, 0, 0); // 3 vertices, 1 instance
    }

    pub const Mesh = struct {
        pipeline: *ColoredVertexPipeline,
        buffer: c.VkBuffer,
        memory: c.VkDeviceMemory,
        vertices: u32,

        pub fn init(pipeline: *ColoredVertexPipeline, vertices: []Vertex) !Mesh {
            const vertexBufferResult = try buffer.createBuffer(
                pipeline.context.physicalDevice,
                pipeline.context.logicalDevice,
                @sizeOf(Vertex) * vertices.len,
                c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            );
            const vertexBuffer = vertexBufferResult.buffer;
            const vertexBufferMemory = vertexBufferResult.memory;

            var data: ?*anyopaque = undefined;
            try vk.checkResult(c.vkMapMemory(
                pipeline.context.logicalDevice,
                vertexBufferMemory,
                0,
                @sizeOf(Vertex) * vertices.len,
                0,
                &data,
            ));

            // Copy vertex data
            const mapped = @as([*]Vertex, @ptrCast(@alignCast(data)));
            @memcpy(mapped[0..vertices.len], vertices.ptr);

            // Unmap
            c.vkUnmapMemory(pipeline.context.logicalDevice, vertexBufferMemory);

            return Mesh{
                .pipeline = pipeline,
                .buffer = vertexBuffer,
                .memory = vertexBufferMemory,
                .vertices = @intCast(vertices.len),
            };
        }

        pub fn deinit(self: *const Mesh) void {
            const logicalDevice = self.pipeline.context.logicalDevice;
            buffer.freeMemory(logicalDevice, self.memory);
            buffer.destroyBuffer(logicalDevice, self.buffer);
        }
    };

    pub const TransformUBO = struct {
        descriptorSet: c.VkDescriptorSet,
        memory: c.VkDeviceMemory,
        buffer: c.VkBuffer,
        pipeline: *ColoredVertexPipeline,

        pub fn init(pipeline: *ColoredVertexPipeline) !TransformUBO {
            const logicalDevice = pipeline.context.logicalDevice;

            const uniformBufferSize = @sizeOf([16]f32) * 2; // mat4
            const uniformBufferResult = try buffer.createBuffer(
                pipeline.context.physicalDevice,
                logicalDevice,
                uniformBufferSize,
                c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            );
            const uniformBuffer = uniformBufferResult.buffer;
            const uniformBufferMemory = uniformBufferResult.memory;

            const descriptorSet = try descriptor.allocateDescriptorSet(
                logicalDevice,
                pipeline.descriptorPool,
                pipeline.descriptorSetLayout,
            );

            descriptor.updateDescriptorSet(logicalDevice, descriptorSet, uniformBuffer, uniformBufferSize);

            return TransformUBO{
                .pipeline = pipeline,
                .descriptorSet = descriptorSet,
                .buffer = uniformBuffer,
                .memory = uniformBufferMemory,
            };
        }

        pub fn update(self: *TransformUBO, transform: ?*Mat4, projection: ?*Mat4) !void {
            const logicalDevice = self.pipeline.context.logicalDevice;
            var data: ?*anyopaque = undefined;
            try vk.checkResult(c.vkMapMemory(logicalDevice, self.memory, 0, @sizeOf(Mat4) * 2, 0, &data));
            const dest: [*]f32 = @ptrCast(@alignCast(data));
            if (transform) |source| {
                @memcpy(dest[0..16], &source.m);
            }
            if (projection) |source| {
                @memcpy(dest[16..32], &source.m);
            }
            c.vkUnmapMemory(logicalDevice, self.memory);
        }

        pub fn deinit(self: *TransformUBO) !void {
            const logicalDevice = self.pipeline.context.logicalDevice;
            try descriptor.destroyDescriptorSet(
                logicalDevice,
                self.pipeline.descriptorPool,
                &self.descriptorSet,
            );
            buffer.freeMemory(logicalDevice, self.memory);
            buffer.destroyBuffer(logicalDevice, self.buffer);
        }
    };
};
