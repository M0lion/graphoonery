const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan/vk.zig");
const c = vk.c;
const windows = @import("windows/window.zig");
const VulkanContext = @import("vulkan/vulkanContext.zig").VulkanContext;
const sc = @import("vulkan/swapchain.zig");
const imageView = @import("vulkan/imageView.zig");
const rp = @import("vulkan/renderPass.zig");
const pipeline = @import("vulkan/pipeline.zig");
const framebuffer = @import("vulkan/framebuffer.zig");
const command = @import("vulkan/command.zig");
const sync = @import("vulkan/sync.zig");
const buffer = @import("vulkan/buffer.zig");
const descriptor = @import("vulkan/descriptor.zig");
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

    var vertCreateInfo = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = vertShaderCode.len,
        .pCode = @ptrCast(@alignCast(vertShaderCode.ptr)),
    };

    var vertShaderModule: c.VkShaderModule = undefined;
    try vk.checkResult(c.vkCreateShaderModule(logicalDevice, &vertCreateInfo, null, &vertShaderModule));

    var fragCreateInfo = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = fragShaderCode.len,
        .pCode = @ptrCast(@alignCast(fragShaderCode.ptr)),
    };

    var fragShaderModule: c.VkShaderModule = undefined;
    try vk.checkResult(c.vkCreateShaderModule(logicalDevice, &fragCreateInfo, null, &fragShaderModule));

    std.log.debug("Creating uniform buffer", .{});
    const uniformBufferSize = @sizeOf([16]f32); // mat4
    const uniformBufferResult = try buffer.createBuffer(
        vulkanContext.physicalDevice,
        logicalDevice,
        uniformBufferSize,
        c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
    const uniformBuffer = uniformBufferResult.buffer;
    const uniformBufferMemory = uniformBufferResult.memory;

    std.log.debug("Creating descriptor set layout", .{});
    const descriptorSetLayout = try descriptor.createDescriptorSetLayout(logicalDevice);

    std.log.debug("Creating descriptor pool", .{});
    const descriptorPool = try descriptor.createDescriptorPool(logicalDevice);

    std.log.debug("Allocating descriptor set", .{});
    const descriptorSet = try descriptor.allocateDescriptorSet(
        logicalDevice,
        descriptorPool,
        descriptorSetLayout,
    );

    descriptor.updateDescriptorSet(logicalDevice, descriptorSet, uniformBuffer, uniformBufferSize);

    std.log.debug("Creating pipeline", .{});
    const pipelineResult = try pipeline.createGraphicsPipeline(.{
        .logicalDevice = logicalDevice,
        .vertShaderModule = vertShaderModule,
        .fragShaderModule = fragShaderModule,
        .width = width,
        .height = height,
        .renderPass = renderPass,
        .descriptorSetLayout = descriptorSetLayout,
    });
    const graphicsPipeline = pipelineResult.pipeline;

    std.log.debug("Cleaning up shaders", .{});
    c.vkDestroyShaderModule(logicalDevice, vertShaderModule, null);
    c.vkDestroyShaderModule(logicalDevice, fragShaderModule, null);

    std.log.debug("Creating framebuffers", .{});
    const swapchainFramebuffers = try framebuffer.createFramebuffers(
        allocator,
        logicalDevice,
        swapchainImageViews,
        renderPass,
        width,
        height,
    );

    std.log.debug("Creating command pool", .{});
    const commandPool = try command.createCommandPool(logicalDevice, queueFamily);

    std.log.debug("Allocating command buffers", .{});
    const commandBuffer = try command.allocateCommandBuffer(logicalDevice, commandPool);

    std.log.debug("Creating sync objects", .{});
    const syncObjects = try sync.createSyncObjects(logicalDevice);
    const imageAvailableSemaphore = syncObjects.imageAvailableSemaphore;
    const renderFinishedSemaphore = syncObjects.renderFinishedSemaphore;
    const inFlightFence = syncObjects.inFlightFence;

    // Flush all Wayland requests before rendering
    if (builtin.os.tag != .macos) {
        if (window.windowHandle.display) |display| {
            _ = wayland_c.c.wl_display_flush(display);
        }
    }

    // Event loop
    var time: f32 = 0.0;
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
            pipelineResult.layout,
            renderFinishedSemaphore,
            queue,
            uniformBufferMemory,
            descriptorSet,
            time,
        );
        time += 0.01;
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
    pipelineLayout: c.VkPipelineLayout,
    renderFinishedSemaphore: c.VkSemaphore,
    queue: c.VkQueue,
    uniformBufferMemory: c.VkDeviceMemory,
    descriptorSet: c.VkDescriptorSet,
    time: f32,
) !void {
    // 1. Update uniform buffer with rotation
    var data: ?*anyopaque = undefined;
    try vk.checkResult(c.vkMapMemory(logicalDevice, uniformBufferMemory, 0, @sizeOf([16]f32), 0, &data));

    const angle = time;
    const cos_a = @cos(angle);
    const sin_a = @sin(angle);

    // Create a 2D rotation matrix in mat4 format
    const transform = [16]f32{
        cos_a, -sin_a, 0.0, 0.0,
        sin_a,  cos_a, 0.0, 0.0,
        0.0,    0.0,   1.0, 0.0,
        0.0,    0.0,   0.0, 1.0,
    };

    const dest: [*]f32 = @ptrCast(@alignCast(data));
    @memcpy(dest[0..16], &transform);
    c.vkUnmapMemory(logicalDevice, uniformBufferMemory);

    // 2. Wait for the previous frame to finish
    try vk.checkResult(c.vkWaitForFences(logicalDevice, 1, &inFlightFence, c.VK_TRUE, std.math.maxInt(u64)));
    try vk.checkResult(c.vkResetFences(logicalDevice, 1, &inFlightFence));

    // 3. Acquire an image from the swapchain
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

    // Bind pipeline, descriptor set, and draw
    c.vkCmdBindPipeline(commandBuffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline);
    c.vkCmdBindDescriptorSets(
        commandBuffer,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        pipelineLayout,
        0,
        1,
        &descriptorSet,
        0,
        null,
    );
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
