const std = @import("std");
const builtin = @import("builtin");
const vk = @import("windows/vk.zig");
const c = vk.c;
const windows = @import("windows/window.zig");
const wayland_c = if (builtin.os.tag != .macos) @import("windows/wayland_c.zig") else struct {
    const c = struct {};
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    var allocator = gpa.allocator();

    var window = try windows.Window.init(allocator);
    defer window.deinit();

    std.debug.print("Surface value: {any}\n", .{window.surface});
    std.debug.print("Instance value: {any}\n", .{window.instance});

    const width, const height = window.getWindowSize();

    const instance = window.instance;

    var deviceCount: u32 = 0;
    try vk.checkResult(c.vkEnumeratePhysicalDevices(instance, &deviceCount, null));
    const physicalDevices = try allocator.alloc(c.VkPhysicalDevice, deviceCount);
    try vk.checkResult(c.vkEnumeratePhysicalDevices(instance, &deviceCount, physicalDevices.ptr));
    std.log.info("{}", .{deviceCount});

    var physicalDeviceIndex: ?usize = null;

    var graphicsFamily: ?usize = null;
    var presentFamily: ?usize = null;
    var physicalDevice: c.VkPhysicalDevice = undefined;
    for (physicalDevices, 0..) |device, deviceIndex| {
        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(device, &properties);
        std.log.info("{s}", .{properties.deviceName});

        var queueFamilyCount: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
        const queueFamilies = try allocator.alloc(c.VkQueueFamilyProperties, queueFamilyCount);
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);

        // Get queue families
        for (queueFamilies, 0..) |family, i| {
            if (family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
                graphicsFamily = i;
            }

            var presentSupport: c.VkBool32 = c.VK_FALSE;
            try vk.checkResult(c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), window.surface.?, &presentSupport));
            if (presentSupport == c.VK_TRUE) {
                presentFamily = i;
            }

            if (graphicsFamily.? == presentFamily.?) break;
        }

        if (graphicsFamily == null or presentFamily == null) continue;

        var extensionCount: u32 = 0;
        try vk.checkResult(c.vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, null));

        const availableExtensions = try allocator.alloc(c.VkExtensionProperties, extensionCount);
        try vk.checkResult(c.vkEnumerateDeviceExtensionProperties(device, null, &extensionCount, availableExtensions.ptr));

        var hasSwapchain = false;
        for (availableExtensions) |ext| {
            const name = @as([*:0]const u8, @ptrCast(&ext.extensionName));
            if (std.mem.eql(u8, std.mem.span(name), c.VK_KHR_SWAPCHAIN_EXTENSION_NAME)) {
                hasSwapchain = true;
                break;
            }
        }

        if (!hasSwapchain) continue;

        var formatCount: u32 = 0;
        try vk.checkResult(c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, window.surface, &formatCount, null));
        var presentModeCount: u32 = 0;
        try vk.checkResult(c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, window.surface, &presentModeCount, null));

        if (formatCount == 0 or presentModeCount == 0) continue;

        physicalDeviceIndex = deviceIndex;
        physicalDevice = device;
        break;
    }

    if (physicalDeviceIndex == null) return;
    std.log.info("Chosen device: {?}", .{physicalDeviceIndex});

    if (presentFamily.? != graphicsFamily.?) {
        std.log.err("presentFamily {} is not the same as graphicsFamily {}, giving up", .{ presentFamily.?, graphicsFamily.? });
        return;
    }

    // Check Wayland presentation support (like vkcube does)
    if (builtin.os.tag != .macos) {
        const vkGetPhysicalDeviceWaylandPresentationSupportKHR = @as(
            ?*const fn (c.VkPhysicalDevice, u32, ?*wayland_c.c.wl_display) callconv(.c) c.VkBool32,
            @ptrCast(c.vkGetInstanceProcAddr(window.instance, "vkGetPhysicalDeviceWaylandPresentationSupportKHR")),
        );

        if (vkGetPhysicalDeviceWaylandPresentationSupportKHR) |presentSupportFn| {
            const supported = presentSupportFn(physicalDevice, @intCast(presentFamily.?), window.windowHandle.display);
            if (supported == c.VK_FALSE) {
                std.log.err("Wayland presentation not supported on this device", .{});
                return;
            }
            std.log.info("Wayland presentation supported", .{});
        } else {
            std.log.warn("vkGetPhysicalDeviceWaylandPresentationSupportKHR not available", .{});
        }
    }

    // Create logical device
    const queuePriority: f32 = 1.0;
    const queueCreateInfo = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueFamilyIndex = @intCast(presentFamily.?),
        .queueCount = 1,
        .pQueuePriorities = &queuePriority,
    };
    const deviceExtensions = [_][*:0]const u8{
        c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
    };
    const createInfo = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queueCreateInfo,
        .queueCreateInfoCount = 1,
        .pEnabledFeatures = null,
        .enabledExtensionCount = deviceExtensions.len,
        .ppEnabledExtensionNames = &deviceExtensions,
    };
    var logicalDevice: c.VkDevice = null;
    try vk.checkResult(c.vkCreateDevice(physicalDevice, &createInfo, null, &logicalDevice));
    var queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(logicalDevice, @intCast(presentFamily.?), 0, &queue);

    std.log.debug("Getting capabilities", .{});
    var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    try vk.checkResult(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, window.surface, &capabilities));

    var formatCount: u32 = 0;
    try vk.checkResult(c.vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, window.surface, &formatCount, null));
    std.debug.print("Available formats: {}\n", .{formatCount});

    const formats = try allocator.alloc(c.VkSurfaceFormatKHR, formatCount);
    defer allocator.free(formats);
    try vk.checkResult(c.vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, window.surface, &formatCount, formats.ptr));

    // Print available formats
    for (formats, 0..) |format, i| {
        std.debug.print("  Format {}: format={}, colorSpace={}\n", .{ i, format.format, format.colorSpace });
    }

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
    std.debug.print("Chosen format: format={}, colorSpace={}\n", .{ chosenFormat.format, chosenFormat.colorSpace });

    var presentModeCount: u32 = 0;
    try vk.checkResult(c.vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, window.surface, &presentModeCount, null));
    std.debug.print("Available present modes: {}\n", .{presentModeCount});

    const presentModes = try allocator.alloc(c.VkPresentModeKHR, presentModeCount);
    defer allocator.free(presentModes);
    try vk.checkResult(c.vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, window.surface, &presentModeCount, presentModes.ptr));

    for (presentModes, 0..) |mode, i| {
        std.debug.print("  Mode {}: {}\n", .{ i, mode });
    }

    // Choose present mode - prefer FIFO (vsync) for Wayland compatibility, fallback to first available
    var chosenPresentMode = presentModes[0];
    for (presentModes) |mode| {
        if (mode == c.VK_PRESENT_MODE_FIFO_KHR) {
            chosenPresentMode = mode;
            break;
        }
    }
    std.debug.print("Using present mode: {}\n", .{chosenPresentMode});

    var chosenImageCount = capabilities.minImageCount + 1;
    if (capabilities.maxImageCount > 0 and chosenImageCount > capabilities.maxImageCount) {
        chosenImageCount = capabilities.maxImageCount;
    }
    std.debug.print("Using image count: {}\n", .{chosenImageCount});

    // Choose composite alpha
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

    const swapchainImageFormat = chosenFormat.format;
    var swapChainCreateInfo = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = window.surface,
        .minImageCount = chosenImageCount,
        .imageFormat = swapchainImageFormat,
        .imageColorSpace = chosenFormat.colorSpace,
        .imageExtent = c.VkExtent2D{
            .width = width,
            .height = height,
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
        .presentMode = chosenPresentMode,
        .oldSwapchain = null,
    };

    std.log.debug("Creating swapchain", .{});
    // Flush Wayland requests before creating swapchain
    if (builtin.os.tag != .macos) {
        if (window.windowHandle.display) |display| {
            _ = wayland_c.c.wl_display_flush(display);
        }
    }
    var swapchain: c.VkSwapchainKHR = undefined;
    vk.checkResult(c.vkCreateSwapchainKHR(logicalDevice, &swapChainCreateInfo, null, &swapchain)) catch |err| {
        std.log.err("Failed to create swapchain: {}\ncapabilities: {any}\ncreate info: {any}", .{ err, capabilities, swapChainCreateInfo });
        return;
    };

    // Commit surface after swapchain creation for Wayland
    if (builtin.os.tag != .macos) {
        if (window.windowHandle.surface) |wlSurface| {
            wayland_c.c.wl_surface_commit(wlSurface);
        }
        if (window.windowHandle.display) |display| {
            _ = wayland_c.c.wl_display_roundtrip(display);
        }
    }

    std.log.debug("Creating image views", .{});
    var imageCount: u32 = 0;
    try vk.checkResult(c.vkGetSwapchainImagesKHR(logicalDevice, swapchain, &imageCount, null));
    const swapchainImages = try allocator.alloc(c.VkImage, imageCount);
    try vk.checkResult(c.vkGetSwapchainImagesKHR(logicalDevice, swapchain, &imageCount, swapchainImages.ptr));
    const swapchainImageViews = try allocator.alloc(c.VkImageView, imageCount);
    for (swapchainImages, 0..) |image, imageIndex| {
        var imageViewCreateInfo = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = swapchainImageFormat,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        try vk.checkResult(c.vkCreateImageView(logicalDevice, &imageViewCreateInfo, null, &swapchainImageViews[imageIndex]));
    }

    std.log.debug("Creating render pass", .{});
    // 1. Describe the color attachment
    var colorAttachment = c.VkAttachmentDescription{
        .flags = 0,
        .format = swapchainImageFormat, // Same format as your swapchain
        .samples = c.VK_SAMPLE_COUNT_1_BIT, // No multisampling
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR, // Clear to a color at start
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE, // Store the result
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE, // No stencil
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED, // Don't care about initial layout
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, // Ready for presentation
    };

    // 2. Reference the attachment in a subpass
    var colorAttachmentRef = c.VkAttachmentReference{
        .attachment = 0, // Index in the attachment descriptions array
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    // 3. Create a subpass
    var subpass = c.VkSubpassDescription{
        .flags = 0,
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &colorAttachmentRef,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .pResolveAttachments = null,
        .pDepthStencilAttachment = null,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    };

    // 4. Create the render pass
    var createRenderPassInfo = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = 1,
        .pAttachments = &colorAttachment,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 0,
        .pDependencies = null,
    };

    var renderPass: c.VkRenderPass = undefined;
    try vk.checkResult(c.vkCreateRenderPass(logicalDevice, &createRenderPassInfo, null, &renderPass));

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

    for (swapchainImageViews, 0..) |imageView, i| {
        const attachments = [_]c.VkImageView{imageView};

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
        .queueFamilyIndex = @intCast(graphicsFamily.?),
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
