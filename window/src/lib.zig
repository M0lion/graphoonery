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

    const window = c.glfwCreateWindow(500, 500, "Test", null, null) orelse
        @panic("Could not create window");

    const display = c.glfwGetWaylandDisplay();
    const surface = c.glfwGetWaylandWindow(window);
    var context = try vulkan.context.VulkanContext.init(.{
        .display = @ptrCast(display),
        .surface = @ptrCast(surface),
    }, 500, 500, allocator);

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();

        _ = try context.beginDraw();

        try context.endDraw();
    }

    c.glfwDestroyWindow(window);
}
