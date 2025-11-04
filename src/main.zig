const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan/vk.zig");
const c = vk.c;
const windows = @import("windows/window.zig");
const VulkanContext = @import("vulkan/vulkanContext.zig").VulkanContext;
const sc = @import("vulkan/swapchain.zig");
const pipeline = @import("vulkan/pipeline.zig");
const command = @import("vulkan/command.zig");
const sync = @import("vulkan/sync.zig");
const buffer = @import("vulkan/buffer.zig");
const descriptor = @import("vulkan/descriptor.zig");
const wayland_c = if (builtin.os.tag != .macos) @import("windows/wayland_c.zig") else struct {
    const c = struct {};
};
const math = @import("math/index.zig");
const shaders = @import("shaders");
const vertShaderCode = shaders.vertex_vert_spv;
const fragShaderCode = shaders.fragment_frag_spv;
const ColoredVertexPipeline = @import("coloredVertexPipeline.zig").ColoredVertexPipeline;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

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
    std.log.debug("Loading shaders", .{});

    var coloredVertexPipeline = try ColoredVertexPipeline.init(vulkanContext);
    defer coloredVertexPipeline.deinit();

    var transform = try ColoredVertexPipeline.TransformUBO.init(&coloredVertexPipeline);
    defer transform.deinit() catch |err| {
        std.log.err("Failed to free transform: {}", .{err});
    };

    std.log.debug("Creating command pool", .{});
    const commandPool = try command.createCommandPool(logicalDevice, queueFamily);
    defer command.destroyCommandPool(logicalDevice, commandPool);

    std.log.debug("Allocating command buffers", .{});
    const commandBuffer = try command.allocateCommandBuffer(logicalDevice, commandPool);
    defer command.freeCommandBuffer(logicalDevice, commandPool, commandBuffer);

    std.log.debug("Creating sync objects", .{});
    const syncObjects = try sync.createSyncObjects(logicalDevice);
    const imageAvailableSemaphore = syncObjects.imageAvailableSemaphore;
    const renderFinishedSemaphore = syncObjects.renderFinishedSemaphore;
    const inFlightFence = syncObjects.inFlightFence;
    defer sync.destroySemaphore(logicalDevice, imageAvailableSemaphore);
    defer sync.destroySemaphore(logicalDevice, renderFinishedSemaphore);
    defer sync.destroyFence(logicalDevice, inFlightFence);

    // Flush all Wayland requests before rendering
    if (builtin.os.tag != .macos) {
        if (window.windowHandle.display) |display| {
            _ = wayland_c.c.wl_display_flush(display);
        }
    }

    var width, var height = window.getWindowSize();
    var aspect =
        @as(f32, @floatFromInt(width)) /
        @as(f32, @floatFromInt(height));

    var t = math.Mat4.identity();
    var p = math.Mat4.createPerspective(90, aspect, 0.01, 10);
    try transform.update(&t, &p);

    // Event loop
    var time: f32 = 0.0;
    while (window.pollEvents()) {
        width, height = window.getWindowSize();
        t = math.Mat4.createRotation(time * 10, time * 6, time * 3);
        t = math.Mat4.createTranslation(0, 0, -5).multiply(&t);
        if (vulkanContext.width != width or vulkanContext.height != height) {
            try vulkanContext.resize();
            aspect =
                @as(f32, @floatFromInt(width)) /
                @as(f32, @floatFromInt(height));
            p = math.Mat4.createPerspective(90, aspect, 0.01, 10);
            try transform.update(&t, &p);
        } else {
            try transform.update(&t, null);
        }

        try render(
            logicalDevice,
            inFlightFence,
            vulkanContext.swapchain,
            imageAvailableSemaphore,
            commandBuffer,
            vulkanContext.renderPass,
            vulkanContext.framebuffers,
            width,
            height,
            renderFinishedSemaphore,
            queue,
            &coloredVertexPipeline,
            &transform,
        );
        time += 0.001;
        std.Thread.sleep(10 * std.time.ns_per_ms); // Sleep 100ms between frames
    }
    try vk.checkResult(c.vkDeviceWaitIdle(logicalDevice));
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
    renderFinishedSemaphore: c.VkSemaphore,
    queue: c.VkQueue,
    coloredVertexPipeline: *ColoredVertexPipeline,
    trans: *ColoredVertexPipeline.TransformUBO,
) !void {
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
    const clearColor = c.VkClearValue{ .color = .{ .float32 = [_]f32{ 0.0, 0.31, 0.8, 1.0 } } };

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

    const viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(width),
        .height = @floatFromInt(height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    c.vkCmdSetViewport(commandBuffer, 0, 1, &viewport);

    const scissor = c.VkRect2D{
        .offset = .{
            .x = 0,
            .y = 0,
        },
        .extent = .{
            .width = width,
            .height = height,
        },
    };
    c.vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

    try coloredVertexPipeline.draw(commandBuffer, trans);

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
    //try vk.checkResult(c.vkQueueWaitIdle(queue));

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
