const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vk.zig");
const c = vk.c;
const sync = @import("sync.zig");
const iv = @import("imageView.zig");

pub const SwapchainImage = struct {
    image: c.VkImage,
    signalSemaphore: c.VkSemaphore,
    imageView: c.VkImageView,

    pub fn deinit(self: *SwapchainImage, logicalDevice: c.VkDevice) void {
        c.vkDestroySemaphore(logicalDevice, self.signalSemaphore, null);
        c.vkDestroyImageView(logicalDevice, self.imageView, null);
    }
};

pub fn getSurfaceFormat(
    allocator: std.mem.Allocator,
    physicalDevice: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !c.VkSurfaceFormatKHR {
    var formatCount: u32 = 0;
    try vk.checkResult(c.vkGetPhysicalDeviceSurfaceFormatsKHR(
        physicalDevice,
        surface,
        &formatCount,
        null,
    ));
    std.debug.print("Available formats: {}\n", .{formatCount});

    const formats = try allocator.alloc(c.VkSurfaceFormatKHR, formatCount);
    defer allocator.free(formats);
    try vk.checkResult(c.vkGetPhysicalDeviceSurfaceFormatsKHR(
        physicalDevice,
        surface,
        &formatCount,
        formats.ptr,
    ));

    // Choose format - look for BGRA8_SRGB, otherwise use first
    var chosenFormat = formats[0];
    for (formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and
            format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        {
            chosenFormat = format;
            break;
        }
    }
    std.debug.print(
        "Chosen format: format={}, colorSpace={}\n",
        .{ chosenFormat.format, chosenFormat.colorSpace },
    );

    return chosenFormat;
}

pub fn getPresentMode(
    allocator: std.mem.Allocator,
    physicalDevice: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !c.VkPresentModeKHR {
    var presentModeCount: u32 = 0;
    try vk.checkResult(c.vkGetPhysicalDeviceSurfacePresentModesKHR(
        physicalDevice,
        surface,
        &presentModeCount,
        null,
    ));
    std.debug.print("Available present modes: {}\n", .{presentModeCount});

    const presentModes = try allocator.alloc(c.VkPresentModeKHR, presentModeCount);
    defer allocator.free(presentModes);
    try vk.checkResult(c.vkGetPhysicalDeviceSurfacePresentModesKHR(
        physicalDevice,
        surface,
        &presentModeCount,
        presentModes.ptr,
    ));

    for (presentModes, 0..) |mode, i| {
        std.debug.print("  Mode {}: {}\n", .{ i, mode });
    }

    // Choose present mode - prefer FIFO (vsync) for Wayland compatibility, fallback to first available
    var chosenPresentMode = presentModes[0];
    for (presentModes) |mode| {
        if (mode == c.VK_PRESENT_MODE_IMMEDIATE_KHR) {
            chosenPresentMode = mode;
            break;
        }
    }
    std.debug.print("Using present mode: {}\n", .{chosenPresentMode});

    return chosenPresentMode;
}

fn getImageCount(capabilities: c.VkSurfaceCapabilitiesKHR) u32 {
    var chosenImageCount = capabilities.minImageCount + 1;
    if (capabilities.maxImageCount > 0 and chosenImageCount > capabilities.maxImageCount) {
        chosenImageCount = capabilities.maxImageCount;
    }
    std.debug.print("Using image count: {}\n", .{chosenImageCount});
    return chosenImageCount;
}

fn getCompositeAlpha(capabilities: c.VkSurfaceCapabilitiesKHR) c.VkCompositeAlphaFlagBitsKHR {
    var compositeAlpha: c.VkCompositeAlphaFlagBitsKHR = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    if ((capabilities.supportedCompositeAlpha & c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR) == 0) {
        if ((capabilities.supportedCompositeAlpha & c.VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR) != 0) {
            compositeAlpha = c.VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR;
        } else if ((capabilities.supportedCompositeAlpha & c.VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR) != 0) {
            compositeAlpha = c.VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR;
        } else {
            compositeAlpha = c.VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
        }
    }
    std.debug.print("Using composite alpha: {}\n", .{compositeAlpha});
    return compositeAlpha;
}

pub const SwapchainConfig = struct {
    physicalDevice: c.VkPhysicalDevice,
    logicalDevice: c.VkDevice,
    surface: c.VkSurfaceKHR,
    surfaceFormat: c.VkSurfaceFormatKHR,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,
};

pub fn createSwapchain(config: SwapchainConfig) !c.VkSwapchainKHR {
    std.log.debug("Getting capabilities", .{});
    var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    try vk.checkResult(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
        config.physicalDevice,
        config.surface,
        &capabilities,
    ));

    const presentMode = try getPresentMode(config.allocator, config.physicalDevice, config.surface);
    const imageCount = getImageCount(capabilities);
    const compositeAlpha = getCompositeAlpha(capabilities);

    var swapChainCreateInfo = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = config.surface,
        .minImageCount = imageCount,
        .imageFormat = config.surfaceFormat.format,
        .imageColorSpace = config.surfaceFormat.colorSpace,
        .imageExtent = c.VkExtent2D{
            .width = config.width,
            .height = config.height,
        },
        .pNext = null,
        .flags = 0,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = compositeAlpha,
        .clipped = c.VK_TRUE,
        .presentMode = presentMode,
        .oldSwapchain = null,
    };

    std.log.debug("Creating swapchain", .{});
    var swapchain: c.VkSwapchainKHR = undefined;
    vk.checkResult(c.vkCreateSwapchainKHR(
        config.logicalDevice,
        &swapChainCreateInfo,
        null,
        &swapchain,
    )) catch |err| {
        std.log.err("Failed to create swapchain: {}\ncapabilities: {any}\ncreate info: {any}", .{
            err,
            capabilities,
            swapChainCreateInfo,
        });
        return err;
    };

    return swapchain;
}

pub fn getSwapchainImages(
    allocator: std.mem.Allocator,
    logicalDevice: c.VkDevice,
    swapchain: c.VkSwapchainKHR,
    format: c.VkFormat,
) ![]SwapchainImage {
    var imageCount: u32 = 0;
    try vk.checkResult(c.vkGetSwapchainImagesKHR(logicalDevice, swapchain, &imageCount, null));

    const images = try allocator.alloc(c.VkImage, imageCount);
    try vk.checkResult(c.vkGetSwapchainImagesKHR(logicalDevice, swapchain, &imageCount, images.ptr));

    const swapChainImages = try allocator.alloc(SwapchainImage, imageCount);
    for (images, 0..) |image, i| {
        swapChainImages[i] = SwapchainImage{
            .image = image,
            .signalSemaphore = try sync.createSemaphore(logicalDevice),
            .imageView = try iv.createImageView(logicalDevice, image, format),
        };
    }

    return swapChainImages;
}
