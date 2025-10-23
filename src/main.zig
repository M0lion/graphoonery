const std = @import("std");
const builtin = @import("builtin");
const vk = @import("windows/vk.zig");
const c = vk.c;
const wayland = @import("windows/wayland.zig");
const windows = @import("windows/window.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    var allocator = gpa.allocator();

    var window = try windows.Window.init(allocator);
    defer window.deinit();

    const width, const height = window.getWindowSize();

    // Create Vulkan instance
    const app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "Vulkan Triangle",
        .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = vk.API_VERSION_1_0,
    };

    // Simpler extension list for older MoltenVK
    const extensions = if (builtin.os.tag == .macos)
        [_][*:0]const u8{
            c.VK_KHR_SURFACE_EXTENSION_NAME,
            c.VK_EXT_METAL_SURFACE_EXTENSION_NAME,
        }
    else
        [_][*:0]const u8{
            c.VK_KHR_SURFACE_EXTENSION_NAME,
            c.VK_KHR_SURFACE_EXTENSION_NAME,
            c.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME,
        };

    const instance_create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0, // Remove portability enumeration flag
        .pApplicationInfo = &app_info,
        .enabledLayerCount = 0,
        .ppEnabledLayerNames = null,
        .enabledExtensionCount = extensions.len,
        .ppEnabledExtensionNames = &extensions,
    };

    var instance: vk.Instance = undefined;
    try vk.checkResult(c.vkCreateInstance(&instance_create_info, null, &instance));
    defer c.vkDestroyInstance(instance, null);

    std.debug.print("Vulkan instance and surface created successfully!\n", .{});
    std.debug.print("Width: {}, Height: {}\n", .{ width, height });

    var deviceCount: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(instance, &deviceCount, null);
    const physicalDevices = try allocator.alloc(c.VkPhysicalDevice, deviceCount);
    _ = c.vkEnumeratePhysicalDevices(instance, &deviceCount, physicalDevices.ptr);
    std.log.info("{}", .{deviceCount});
    for (physicalDevices) |device| {
        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(device, &properties);
        std.log.info("{s}", .{properties.deviceName});

        var queueFamilyCount: u32 = 0;
        _ = c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
        const queueFamilies = try allocator.alloc(c.VkQueueFamilyProperties, queueFamilyCount);
        _ = c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);
    }

    // Event loop
    while (windows.Window.pollEvents()) {
        std.Thread.sleep(16_000_000);
    }
}
