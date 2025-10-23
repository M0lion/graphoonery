const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vk.zig");
const c = vk.c;

const EventType = enum(c_int) {
    none = 0,
    mouse_down = 1,
    mouse_up = 2,
    mouse_moved = 5,
    key_down = 10,
    key_up = 11,
    scroll_wheel = 22,
    _,
};

const MacEvent = extern struct {
    type: EventType,
    key_code: u16,
    mouse_x: f64,
    mouse_y: f64,
    delta_x: f64,
    delta_y: f64,
};

extern fn createMacWindow() ?*anyopaque;
extern fn pollMacEvent(event: *MacEvent) bool;
extern fn releaseMacWindow(?*anyopaque) void;
extern fn getMetalLayer(window: *anyopaque) *anyopaque;
extern fn getWindowSize(window: *anyopaque, width: *c_int, height: *c_int) void;

pub fn main() !void {
    const window = createMacWindow() orelse return error.WindowCreationFailed;
    defer releaseMacWindow(window);

    var width: c_int = 0;
    var height: c_int = 0;
    getWindowSize(window, &width, &height);

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

    // Create surface
    var surface: vk.SurfaceKHR = undefined;
    if (builtin.os.tag == .macos) {
        const metal_layer = getMetalLayer(window);
        const surface_create_info = c.VkMetalSurfaceCreateInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
            .pNext = null,
            .flags = 0,
            .pLayer = metal_layer,
        };
        try vk.checkResult(c.vkCreateMetalSurfaceEXT(instance, &surface_create_info, null, &surface));
    } else {
        // Wayland surface - you'll need wl_display and wl_surface pointers
        @compileError("Wayland surface creation not implemented");
    }
    defer c.vkDestroySurfaceKHR(instance, surface, null);

    std.debug.print("Vulkan instance and surface created successfully!\n", .{});
    std.debug.print("Width: {}, Height: {}\n", .{ width, height });

    var gpa = std.heap.DebugAllocator(.{}){};
    var allocator = gpa.allocator();

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
    var event: MacEvent = undefined;
    while (pollMacEvent(&event)) {
        std.Thread.sleep(16_000_000);
    }
}
