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
const wayland_c = if (builtin.os.tag != .macos) @import("../windows/wayland_c.zig") else struct {};
const fb = @import("framebuffer.zig");
const iv = @import("imageView.zig");
const rp = @import("renderPass.zig");

pub const VulkanContextError = error{
    CouldNotFindPDevice,
};

pub const VulkanContext = struct {
    window: *Window,
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
    swapchainImageViews: []c.VkImageView,
    framebuffers: []c.VkFramebuffer,

    pub fn init(window: *Window, allocator: std.mem.Allocator) !VulkanContext {
        const instance = try createInstance(.{
            .name = "Vulkan Test",
        });

        var surface: c.VkSurfaceKHR = null;
        switch (comptime platform) {
            .macos => {
                surface = try s.createMetalSurface(instance, .{ .windowHandle = window.windowHandle });
            },
            .linux => {
                surface = try s.createWaylandSurface(instance, .{
                    .display = window.windowHandle.display,
                    .surface = window.windowHandle.surface,
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
        if (builtin.os.tag != .macos) {
            if (window.windowHandle.display) |display| {
                _ = wayland_c.c.wl_display_flush(display);
            }
        }

        std.log.debug("Getting window dimensions", .{});
        const width, const height = window.getWindowSize();

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
        const swapchainImages = try sc.getSwapchainImages(allocator, logicalDevice, swapchain);
        defer allocator.free(swapchainImages);
        const swapchainImageViews = try iv.createImageViews(
            allocator,
            logicalDevice,
            swapchainImages,
            surfaceFormat.format,
        );

        std.log.debug("Creating render pass", .{});
        const renderPass = try rp.createRenderPass(logicalDevice, surfaceFormat.format);

        std.log.debug("Creating framebuffers", .{});
        const framebuffers = try fb.createFramebuffers(
            allocator,
            logicalDevice,
            swapchainImageViews,
            renderPass,
            width,
            height,
        );

        std.log.debug("Commiting surface", .{});
        window.commit();

        return VulkanContext{
            .window = window,
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
            .swapchainImageViews = swapchainImageViews,
            .framebuffers = framebuffers,
        };
    }

    pub fn resize(self: *VulkanContext) !void {
        //const oldSwapchain = self.swapchain;
        const width, const height = self.window.getWindowSize();
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

        const swapchainImages = try sc.getSwapchainImages(
            self.allocator,
            self.logicalDevice,
            self.swapchain,
        );
        defer self.allocator.free(swapchainImages);
        self.swapchainImageViews = try iv.createImageViews(
            self.allocator,
            self.logicalDevice,
            swapchainImages,
            self.surfaceFormat.format,
        );

        self.framebuffers = try fb.createFramebuffers(
            self.allocator,
            self.logicalDevice,
            self.swapchainImageViews,
            self.renderPass,
            width,
            height,
        );
    }

    fn cleanupSwapchain(self: *VulkanContext) void {
        for (self.framebuffers) |framebuffer| {
            c.vkDestroyFramebuffer(self.logicalDevice, framebuffer, null);
        }

        for (self.swapchainImageViews) |imageView| {
            c.vkDestroyImageView(self.logicalDevice, imageView, null);
        }

        c.vkDestroySwapchainKHR(self.logicalDevice, self.swapchain, null);
    }

    pub fn deinit(self: *VulkanContext) void {
        self.cleanupSwapchain();
        rp.destroyRenderPass(self.logicalDevice, self.renderPass);
        c.vkDestroyDevice(self.logicalDevice, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};
