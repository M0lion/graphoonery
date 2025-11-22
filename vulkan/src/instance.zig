const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;
const builtin = @import("builtin");

pub const ApplicationInfo = struct {
    name: [*c]const u8,
    validationLayersEnabled: bool = false,
};

pub fn createInstance(info: ApplicationInfo) !c.VkInstance {
    // Create Vulkan instance
    const requestedVersion = vk.API_VERSION_1_0;
    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = info.name,
        .apiVersion = requestedVersion,
        // .pNext = null,
        // .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
        // .pEngineName = "No Engine",
        // .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
    };

    var version: u32 = undefined;
    _ = c.vkEnumerateInstanceVersion(&version);
    std.log.info("Version: {} R: {}, {}.{}.{}", .{
        version,
        requestedVersion,
        c.VK_VERSION_MAJOR(version),
        c.VK_VERSION_MINOR(version),
        c.VK_VERSION_PATCH(version),
    });

    // Simpler extension list for older MoltenVK
    const extensions = switch (builtin.os.tag) {
        .macos => [_][*:0]const u8{
            c.VK_KHR_SURFACE_EXTENSION_NAME,
            c.VK_EXT_METAL_SURFACE_EXTENSION_NAME,
            c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
        },
        .linux => [_][*:0]const u8{
            c.VK_KHR_SURFACE_EXTENSION_NAME,
            c.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
                //c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
        },
        else => @compileError("Unsupported os"),
    };

    const layers = [_][*:0]const u8{
        "VK_LAYER_KHRONOS_validation",
    };

    const instance_create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0, // Remove portability enumeration flag
        .pApplicationInfo = &app_info,
        .enabledLayerCount = if (info.validationLayersEnabled) 1 else 0,
        .ppEnabledLayerNames = &layers,
        .enabledExtensionCount = extensions.len,
        .ppEnabledExtensionNames = &extensions,
    };

    std.log.debug("Creating instance", .{});
    var instance: c.VkInstance = null;
    try vk.checkResult(c.vkCreateInstance(&instance_create_info, null, &instance));
    return instance;
}
