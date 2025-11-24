const std = @import("std");
const c = @cImport({
    @cDefine("GLFW_EXPOSE_NATIVE_WAYLAND", "true");
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
});
const vulkan = @import("vulkan");

pub fn init() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    if (c.glfwInit() == c.GLFW_FALSE) {
        @panic("Failed to init glfw");
    }

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

    var width: c_int = 500;
    var height: c_int = 500;

    const window = c.glfwCreateWindow(width, height, "Test", null, null) orelse
        @panic("Could not create window");

    c.glfwPollEvents();

    const display = c.glfwGetWaylandDisplay() orelse @panic("Could not get display");
    const surface = c.glfwGetWaylandWindow(window) orelse @panic("Could not get surface");

    c.glfwGetWindowSize(window, &width, &height);

    var context = try vulkan.context.VulkanContext.init(.{
        .display = @ptrCast(display),
        .surface = @ptrCast(surface),
    }, @intCast(width), @intCast(height), allocator);

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();

        _ = try context.beginDraw();

        try context.endDraw();
    }

    c.glfwDestroyWindow(window);
}
