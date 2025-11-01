const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan/vk.zig");
const c = vk.c;
const windows = @import("windows/window.zig");
const VulkanContext = @import("vulkan/vulkanContext.zig").VulkanContext;
const sc = @import("vulkan/swapchain.zig");
const imageView = @import("vulkan/imageView.zig");
const rp = @import("vulkan/renderPass.zig");
const wayland_c = if (builtin.os.tag != .macos) @import("windows/wayland_c.zig") else struct {
    const c = struct {};
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    var allocator = gpa.allocator();

    std.log.debug("Window init", .{});
    var window = try windows.Window.init(allocator);
    try window.finishInit();
    std.log.debug("Window: {*}", .{&window});
    defer window.deinit();

    std.log.debug("Vulkan init", .{});
    var vulkanContext = try VulkanContext.init(&window, allocator);
    defer vulkanContext.deinit();

    const logicalDevice = vulkanContext.logicalDevice;
    const queue = vulkanContext.queue;
    const queueFamily = vulkanContext.queueFamily;
    const swapchain = vulkanContext.swapchain;
    const swapchainImageFormat = vulkanContext.swapchainImageFormat;
    const width = vulkanContext.swapchainWidth;
    const height = vulkanContext.swapchainHeight;

    std.log.debug("Creating image views", .{});
    const swapchainImages = try sc.getSwapchainImages(allocator, logicalDevice, swapchain);
    defer allocator.free(swapchainImages);
    const swapchainImageViews = try imageView.createImageViews(
        allocator,
        logicalDevice,
        swapchainImages,
        swapchainImageFormat,
    );

    std.log.debug("Creating render pass", .{});
    const renderPass = try rp.createRenderPass(logicalDevice, swapchainImageFormat);

    std.log.debug("Loading shaders", .{});
    const vertShaderCode = @embedFile("shaders/vert.spv");
    const fragShaderCode = @embedFile("shaders/frag.spv");

    // Then create shader modules directly
    var vertCreateInfo = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = vertShaderCode.len,
        .pCode = @ptrCast(@alignCast(vertShaderCode.ptr)),
    };

    var vertShaderModule: c.VkShaderModule = undefined;
    try vk.checkResult(c.vkCreateShaderModule(logicalDevice, &vertCreateInfo, null, &vertShaderModule));

    // Same for fragment shader
    var fragCreateInfo = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = fragShaderCode.len,
        .pCode = @ptrCast(@alignCast(fragShaderCode.ptr)),
    };

    var fragShaderModule: c.VkShaderModule = undefined;
    try vk.checkResult(c.vkCreateShaderModule(logicalDevice, &fragCreateInfo, null, &fragShaderModule));

    const vertShaderStageInfo = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vertShaderModule,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const fragShaderStageInfo = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragShaderModule,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const shaderStages = [_]c.VkPipelineShaderStageCreateInfo{ vertShaderStageInfo, fragShaderStageInfo };

    std.log.debug("Creating pipeline layout", .{});
    // No vertex input
    var vertexInputInfo = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
    };

    // Input assembly - draw triangles
    var inputAssembly = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    // Viewport and scissor (dynamic, we'll set them later)
    var viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(width),
        .height = @floatFromInt(height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    var scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = c.VkExtent2D{
            .width = width,
            .height = height,
        },
    };

    var viewportState = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };

    // Rasterizer
    var rasterizer = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
        .lineWidth = 1.0,
    };

    // No multisampling
    var multisampling = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = c.VK_FALSE,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = c.VK_FALSE,
        .alphaToOneEnable = c.VK_FALSE,
    };

    // Color blending (no blending)
    var colorBlendAttachment = c.VkPipelineColorBlendAttachmentState{
        .blendEnable = c.VK_FALSE,
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT |
            c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
        .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .colorBlendOp = c.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
    };

    var colorBlending = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &colorBlendAttachment,
        .blendConstants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    var pipelineLayoutInfo = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };

    var pipelineLayout: c.VkPipelineLayout = undefined;
    try vk.checkResult(c.vkCreatePipelineLayout(logicalDevice, &pipelineLayoutInfo, null, &pipelineLayout));

    std.log.debug("Creating pipeline", .{});
    var pipelineInfo = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stageCount = 2,
        .pStages = &shaderStages,
        .pVertexInputState = &vertexInputInfo,
        .pInputAssemblyState = &inputAssembly,
        .pViewportState = &viewportState,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = null,
        .pColorBlendState = &colorBlending,
        .pDynamicState = null,
        .layout = pipelineLayout,
        .renderPass = renderPass,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
        .pTessellationState = null,
    };

    var graphicsPipeline: c.VkPipeline = undefined;
    try vk.checkResult(c.vkCreateGraphicsPipelines(logicalDevice, null, 1, &pipelineInfo, null, &graphicsPipeline));

    std.log.debug("Cleaning up shaders", .{});
    c.vkDestroyShaderModule(logicalDevice, vertShaderModule, null);
    c.vkDestroyShaderModule(logicalDevice, fragShaderModule, null);

    std.log.debug("Creating framebuffers", .{});
    var swapchainFramebuffers = try allocator.alloc(c.VkFramebuffer, swapchainImageViews.len);

    for (swapchainImageViews, 0..) |view, i| {
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

        try vk.checkResult(c.vkCreateFramebuffer(logicalDevice, &framebufferInfo, null, &swapchainFramebuffers[i]));
    }

    std.log.debug("Creating command pool", .{});
    var poolInfo = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .pNext = null,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = @intCast(queueFamily),
    };

    var commandPool: c.VkCommandPool = undefined;
    try vk.checkResult(c.vkCreateCommandPool(logicalDevice, &poolInfo, null, &commandPool));

    std.log.debug("Allocating command buffers", .{});
    var allocInfo = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = commandPool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var commandBuffer: c.VkCommandBuffer = undefined;
    try vk.checkResult(c.vkAllocateCommandBuffers(logicalDevice, &allocInfo, &commandBuffer));

    std.log.debug("Creating sync objects", .{});
    // Semaphores for GPU-GPU synchronization
    var imageAvailableSemaphore: c.VkSemaphore = undefined;
    var renderFinishedSemaphore: c.VkSemaphore = undefined;

    // Fence for CPU-GPU synchronization
    var inFlightFence: c.VkFence = undefined;

    var semaphoreInfo = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
    };

    try vk.checkResult(c.vkCreateSemaphore(logicalDevice, &semaphoreInfo, null, &imageAvailableSemaphore));
    try vk.checkResult(c.vkCreateSemaphore(logicalDevice, &semaphoreInfo, null, &renderFinishedSemaphore));

    var fenceInfo = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .pNext = null,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT, // Start signaled so first frame doesn't wait
    };

    try vk.checkResult(c.vkCreateFence(logicalDevice, &fenceInfo, null, &inFlightFence));

    // Flush all Wayland requests before rendering
    if (builtin.os.tag != .macos) {
        if (window.windowHandle.display) |display| {
            _ = wayland_c.c.wl_display_flush(display);
        }
    }

    // Event loop
    while (window.pollEvents()) {
        try render(
            logicalDevice,
            inFlightFence,
            swapchain,
            imageAvailableSemaphore,
            commandBuffer,
            renderPass,
            swapchainFramebuffers,
            width,
            height,
            graphicsPipeline,
            renderFinishedSemaphore,
            queue,
        );
        std.Thread.sleep(100 * std.time.ns_per_ms); // Sleep 100ms between frames
    }
}

fn render(
    logicalDevice: c.VkDevice,
    inFlightFence: c.VkFence,
    swapchain: c.VkSwapchainKHR,
    imageAvailableSemaphore: c.VkSemaphore,
    commandBuffer: c.VkCommandBuffer,
    renderPass: c.VkRenderPass,
    swapchainFramebuffers: []c.VkFramebuffer,
    width: u32,
    height: u32,
    graphicsPipeline: c.VkPipeline,
    renderFinishedSemaphore: c.VkSemaphore,
    queue: c.VkQueue,
) !void {
    // 1. Wait for the previous frame to finish
    try vk.checkResult(c.vkWaitForFences(logicalDevice, 1, &inFlightFence, c.VK_TRUE, std.math.maxInt(u64)));
    try vk.checkResult(c.vkResetFences(logicalDevice, 1, &inFlightFence));

    // 2. Acquire an image from the swapchain
    var imageIndex: u32 = undefined;
    try vk.checkResult(c.vkAcquireNextImageKHR(logicalDevice, swapchain, std.math.maxInt(u64), imageAvailableSemaphore, null, &imageIndex));

    // 3. Reset and record command buffer
    try vk.checkResult(c.vkResetCommandBuffer(commandBuffer, 0));

    var beginInfo = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = 0,
        .pInheritanceInfo = null,
    };
    try vk.checkResult(c.vkBeginCommandBuffer(commandBuffer, &beginInfo));

    // Begin render pass
    const clearColor = c.VkClearValue{ .color = .{ .float32 = [_]f32{ 1.0, 0.0, 0.0, 1.0 } } };

    var renderPassInfo = c.VkRenderPassBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .pNext = null,
        .renderPass = renderPass,
        .framebuffer = swapchainFramebuffers[imageIndex],
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = c.VkExtent2D{
                .width = width,
                .height = height,
            },
        },
        .clearValueCount = 1,
        .pClearValues = &clearColor,
    };

    c.vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, c.VK_SUBPASS_CONTENTS_INLINE);

    // Bind pipeline and draw
    c.vkCmdBindPipeline(commandBuffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline);
    c.vkCmdDraw(commandBuffer, 3, 1, 0, 0); // 3 vertices, 1 instance

    // End render pass and command buffer
    c.vkCmdEndRenderPass(commandBuffer);
    try vk.checkResult(c.vkEndCommandBuffer(commandBuffer));

    // 4. Submit command buffer
    const waitSemaphores = [_]c.VkSemaphore{imageAvailableSemaphore};
    const waitStages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    const signalSemaphores = [_]c.VkSemaphore{renderFinishedSemaphore};

    var submitInfo = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &waitSemaphores,
        .pWaitDstStageMask = &waitStages,
        .commandBufferCount = 1,
        .pCommandBuffers = &commandBuffer,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &signalSemaphores,
    };

    try vk.checkResult(c.vkQueueSubmit(queue, 1, &submitInfo, inFlightFence));

    // Wait for queue to finish (debugging)
    try vk.checkResult(c.vkQueueWaitIdle(queue));

    // 5. Present the image
    const swapchains = [_]c.VkSwapchainKHR{swapchain};

    var presentInfo = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pNext = null,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &signalSemaphores,
        .swapchainCount = 1,
        .pSwapchains = &swapchains,
        .pImageIndices = &imageIndex,
        .pResults = null,
    };

    try vk.checkResult(c.vkQueuePresentKHR(queue, &presentInfo));
}
