const std = @import("std");
const builtin = @import("builtin");
const Window = @import("../windows/window.zig").Window;
const vk = @import("vk.zig");
const c = vk.c;
const platform = @import("../platform.zig").platform;
const macos = @import("../windows/macos.zig");
const createInstance = @import("instance.zig").createInstance;
const s = @import("surface.zig");
const pDevice = @import("physicalDevice.zig");
const lDevice = @import("logicalDevice.zig");
const sc = @import("swapchain.zig");
const fb = @import("framebuffer.zig");
const iv = @import("imageView.zig");
const rp = @import("renderPass.zig");
const sync = @import("sync.zig");
const command = @import("command.zig");
const img = @import("images.zig");

pub const VulkanContextError = error{
    CouldNotFindPDevice,
};

pub const VulkanContext = struct {
    pub const SurfaceData = switch (platform) {
        .linux => struct {
            display: ?*c.struct_wl_display_1,
            surface: ?*c.struct_wl_surface_2,
        },
        .macos => *anyopaque,
    };

    allocator: std.mem.Allocator,
    surface: c.VkSurfaceKHR,
    instance: c.VkInstance,
    physicalDevice: c.VkPhysicalDevice,
    queueFamily: u32,
    logicalDevice: c.VkDevice,
    queue: c.VkQueue,
    swapchain: c.VkSwapchainKHR,
    swapchainImageFormat: c.VkFormat,
    width: u32,
    height: u32,
    surfaceFormat: c.VkSurfaceFormatKHR,
    renderPass: c.VkRenderPass,
    swapchainImages: []sc.SwapchainImage,
    framebuffers: []c.VkFramebuffer,
    syncObjects: sync.SyncObjects,
    commandPool: c.VkCommandPool,
    commandBuffer: c.VkCommandBuffer,
    imageIndex: ?u32 = null,
    depthImageResults: []img.ImageResult,

    pub fn init(surfaceData: SurfaceData, width: u32, height: u32, allocator: std.mem.Allocator) !VulkanContext {
        const instance = try createInstance(.{
            .name = "Vulkan Test",
        });

        var surface: c.VkSurfaceKHR = null;
        switch (comptime platform) {
            .macos => {
                surface = try s.createMetalSurface(instance, .{ .windowHandle = surfaceData });
            },
            .linux => {
                surface = try s.createWaylandSurface(instance, .{
                    .display = surfaceData.display,
                    .surface = surfaceData.surface,
                });
            },
        }

        const physicalDeviceResult = try pDevice.pickPhysicalDevice(
            instance,
            allocator,
            surface,
        ) orelse {
            return VulkanContextError.CouldNotFindPDevice;
        };

        const physicalDevice = physicalDeviceResult.device;
        const queueFamily = physicalDeviceResult.queue;

        const logicalDevice = try lDevice.createLogicalDevice(physicalDevice, queueFamily);

        var queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(logicalDevice, @intCast(queueFamily), 0, &queue);

        // Flush Wayland requests before creating swapchain
        //if (builtin.os.tag != .macos) {
        //    if (window.windowHandle.connection.display) |display| {
        //        _ = wayland_c.c.wl_display_flush(display);
        //    }
        //}

        //std.log.debug("Getting window dimensions", .{});
        //const width, const height = window.getWindowSize();

        const surfaceFormat = try sc.getSurfaceFormat(
            allocator,
            physicalDevice,
            surface,
        );

        const swapchain = try sc.createSwapchain(.{
            .physicalDevice = physicalDevice,
            .logicalDevice = logicalDevice,
            .surface = surface,
            .surfaceFormat = surfaceFormat,
            .width = width,
            .height = height,
            .allocator = allocator,
        });

        std.log.debug("Creating image views", .{});
        const swapchainImages = try sc.getSwapchainImages(
            allocator,
            logicalDevice,
            swapchain,
            surfaceFormat.format,
        );

        std.log.debug("Creating render pass", .{});
        const renderPass = try rp.createRenderPass(logicalDevice, surfaceFormat.format);

        const depthImageResult = try img.createDepthImages(allocator, logicalDevice, physicalDevice, width, height, swapchainImages.len);
        var depthImageViews = try allocator.alloc(c.VkImageView, depthImageResult.len);
        for (depthImageResult, 0..) |result, i| {
            depthImageViews[i] = result.imageView;
        }

        std.log.debug("Creating framebuffers", .{});
        const framebuffers = try fb.createFramebuffers(
            allocator,
            logicalDevice,
            swapchainImages,
            depthImageViews,
            renderPass,
            width,
            height,
        );

        //std.log.debug("Commiting surface", .{});
        //try window.commit();

        const commandPool = try command.createCommandPool(
            logicalDevice,
            queueFamily,
        );

        const commandBuffer = try command.allocateCommandBuffer(
            logicalDevice,
            commandPool,
        );

        const syncObjects = try sync.createSyncObjects(logicalDevice);

        return VulkanContext{
            .allocator = allocator,
            .instance = instance,
            .surface = surface,
            .physicalDevice = physicalDevice,
            .queueFamily = queueFamily,
            .logicalDevice = logicalDevice,
            .queue = queue,
            .swapchain = swapchain,
            .swapchainImageFormat = surfaceFormat.format,
            .width = width,
            .height = height,
            .surfaceFormat = surfaceFormat,
            .renderPass = renderPass,
            .swapchainImages = swapchainImages,
            .framebuffers = framebuffers,
            .syncObjects = syncObjects,
            .commandPool = commandPool,
            .commandBuffer = commandBuffer,
            .depthImageResults = depthImageResult,
        };
    }

    pub fn beginDraw(self: *VulkanContext) !c.VkCommandBuffer {
        const logicalDevice = self.logicalDevice;
        const inFlightFence = self.syncObjects.inFlightFence;
        const imageAvailableSemaphore = self.syncObjects.imageAvailableSemaphore;

        // 2. Wait for the previous frame to finish
        try vk.checkResult(c.vkWaitForFences(logicalDevice, 1, &inFlightFence, c.VK_TRUE, std.math.maxInt(u64)));
        try vk.checkResult(c.vkResetFences(logicalDevice, 1, &inFlightFence));

        // 3. Acquire an image from the swapchain
        var imageIndex: u32 = undefined;
        try vk.checkResult(c.vkAcquireNextImageKHR(
            logicalDevice,
            self.swapchain,
            std.math.maxInt(u64),
            imageAvailableSemaphore,
            null,
            &imageIndex,
        ));
        self.imageIndex = imageIndex;

        // 3. Reset and record command buffer
        try vk.checkResult(c.vkResetCommandBuffer(self.commandBuffer, 0));

        var beginInfo = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .pNext = null,
            .flags = 0,
            .pInheritanceInfo = null,
        };
        try vk.checkResult(c.vkBeginCommandBuffer(self.commandBuffer, &beginInfo));

        // Begin render pass
        const clearColor = [_]c.VkClearValue{
            c.VkClearValue{ .color = .{ .float32 = [_]f32{ 0.0, 0.31, 0.8, 1.0 } } },
            c.VkClearValue{ .depthStencil = .{ .depth = 1, .stencil = 0 } },
        };

        var renderPassInfo = c.VkRenderPassBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .pNext = null,
            .renderPass = self.renderPass,
            .framebuffer = self.framebuffers[imageIndex],
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = c.VkExtent2D{
                    .width = self.width,
                    .height = self.height,
                },
            },
            .clearValueCount = clearColor.len,
            .pClearValues = &clearColor,
        };

        c.vkCmdBeginRenderPass(
            self.commandBuffer,
            &renderPassInfo,
            c.VK_SUBPASS_CONTENTS_INLINE,
        );

        const viewport = c.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @floatFromInt(self.width),
            .height = @floatFromInt(self.height),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        c.vkCmdSetViewport(self.commandBuffer, 0, 1, &viewport);

        const scissor = c.VkRect2D{
            .offset = .{
                .x = 0,
                .y = 0,
            },
            .extent = .{
                .width = self.width,
                .height = self.height,
            },
        };
        c.vkCmdSetScissor(self.commandBuffer, 0, 1, &scissor);
        return self.commandBuffer;
    }

    pub fn endDraw(self: *VulkanContext) !void {
        c.vkCmdEndRenderPass(self.commandBuffer);

        const imageIndex = self.imageIndex orelse return error.NoImageIndex;

        try vk.checkResult(c.vkEndCommandBuffer(self.commandBuffer));

        const waitSemaphores = [_]c.VkSemaphore{
            self.syncObjects.imageAvailableSemaphore,
        };
        const waitStages = [_]c.VkPipelineStageFlags{
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        };
        const signalSemaphores = [_]c.VkSemaphore{
            self.swapchainImages[imageIndex].signalSemaphore,
        };

        var submitInfo = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .pNext = null,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &waitSemaphores,
            .pWaitDstStageMask = &waitStages,
            .commandBufferCount = 1,
            .pCommandBuffers = &self.commandBuffer,
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &signalSemaphores,
        };

        try vk.checkResult(c.vkQueueSubmit(
            self.queue,
            1,
            &submitInfo,
            self.syncObjects.inFlightFence,
        ));

        // 5. Present the image
        const swapchains = [_]c.VkSwapchainKHR{self.swapchain};

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
        self.imageIndex = null;

        try vk.checkResult(c.vkQueuePresentKHR(self.queue, &presentInfo));
    }

    pub fn resize(self: *VulkanContext, width: u32, height: u32) !void {
        //const oldSwapchain = self.swapchain;
        self.width = width;
        self.height = height;
        try vk.checkResult(c.vkDeviceWaitIdle(self.logicalDevice));
        self.cleanupSwapchain();
        self.swapchain = try sc.createSwapchain(.{
            .physicalDevice = self.physicalDevice,
            .logicalDevice = self.logicalDevice,
            .surface = self.surface,
            .surfaceFormat = self.surfaceFormat,
            .width = width,
            .height = height,
            .allocator = self.allocator,
        });

        self.swapchainImages = try sc.getSwapchainImages(
            self.allocator,
            self.logicalDevice,
            self.swapchain,
            self.surfaceFormat.format,
        );

        self.depthImageResults = try img.createDepthImages(
            self.allocator,
            self.logicalDevice,
            self.physicalDevice,
            width,
            height,
            self.swapchainImages.len,
        );
        var depthImageViews = try self.allocator.alloc(
            c.VkImageView,
            self.depthImageResults.len,
        );
        for (self.depthImageResults, 0..) |result, i| {
            depthImageViews[i] = result.imageView;
        }

        self.framebuffers = try fb.createFramebuffers(
            self.allocator,
            self.logicalDevice,
            self.swapchainImages,
            depthImageViews,
            self.renderPass,
            width,
            height,
        );
    }

    fn cleanupSwapchain(self: *VulkanContext) void {
        std.log.debug("Cleaning up swapchain", .{});
        img.freeImages(self.logicalDevice, self.depthImageResults);

        for (self.framebuffers) |framebuffer| {
            c.vkDestroyFramebuffer(self.logicalDevice, framebuffer, null);
        }

        for (self.swapchainImages) |*imageView| {
            imageView.deinit(self.logicalDevice);
        }
        self.allocator.free(self.swapchainImages);

        c.vkDestroySwapchainKHR(self.logicalDevice, self.swapchain, null);
        std.log.debug("Cleaned up swapchain", .{});
    }

    pub fn waitDeviceIdle(self: *VulkanContext) !void {
        try vk.checkResult(c.vkDeviceWaitIdle(self.logicalDevice));
    }

    pub fn deinit(self: *VulkanContext) !void {
        try vk.checkResult(c.vkDeviceWaitIdle(self.logicalDevice));
        sync.destroySemaphore(
            self.logicalDevice,
            self.syncObjects.imageAvailableSemaphore,
        );
        sync.destroyFence(
            self.logicalDevice,
            self.syncObjects.inFlightFence,
        );
        command.freeCommandBuffer(
            self.logicalDevice,
            self.commandPool,
            self.commandBuffer,
        );
        command.destroyCommandPool(
            self.logicalDevice,
            self.commandPool,
        );
        self.cleanupSwapchain();
        rp.destroyRenderPass(self.logicalDevice, self.renderPass);
        c.vkDestroyDevice(self.logicalDevice, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};
