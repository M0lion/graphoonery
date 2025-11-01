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

    std.log.debug("Creating pipeline", .{});
    const pipelineResult = try pipeline.createGraphicsPipeline(.{
        .logicalDevice = logicalDevice,
        .vertShaderModule = vertShaderModule,
        .fragShaderModule = fragShaderModule,
        .width = width,
        .height = height,
        .renderPass = renderPass,
    });
    const graphicsPipeline = pipelineResult.pipeline;
    _ = pipelineResult.layout;

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
