const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;
const macos = @import("../windows/macos.zig");
const wayland = @import("../windows/wayland_c.zig");

pub const CreateMetalSurfaceArgs = struct {
    windowHandle: *anyopaque,
};

pub fn createMetalSurface(
    instance: c.VkInstance,
    args: CreateMetalSurfaceArgs,
) !c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = null;
    const metal_layer = macos.getMetalLayer(args.windowHandle);
    const surface_create_info = c.VkMetalSurfaceCreateInfoEXT{
        .sType = c.VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
        .pNext = null,
        .flags = 0,
        .pLayer = metal_layer,
    };
    try vk.checkResult(c.vkCreateMetalSurfaceEXT(instance, &surface_create_info, null, &surface));
    return surface;
}

pub const CreateWaylandSurfaceArgs = struct {
    display: wayland.c.wl_display,
    surface: wayland.c.wl_surface,
};

pub fn createWaylandSurface(
    instance: c.VkInstance,
    args: CreateWaylandSurfaceArgs,
) !c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = null;
    const surface_create_info = c.VkWaylandSurfaceCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
        .display = @ptrCast(@alignCast(args.display)),
        .surface = @ptrCast(@alignCast(args.surface)),
        .pNext = null,
        .flags = 0,
    };
    try vk.checkResult(c.vkCreateWaylandSurfaceKHR(instance, &surface_create_info, null, &surface));
}
