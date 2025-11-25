const std = @import("std");
const glfw = @import("glfw.zig");
const c = glfw.c;
const vulkan = @import("vulkan");
const in = @import("input.zig");

pub const Window = struct {
    glfwWindow: *c.struct_GLFWwindow,
    input: in.Input,

    pub fn init(width: u32, height: u32) Window {
        if (c.glfwInit() == c.GLFW_FALSE) {
            @panic("Failed to init glfw");
        }

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

        const window = c.glfwCreateWindow(@intCast(width), @intCast(height), "Test", null, null) orelse
            @panic("Could not create window");

        return Window{
            .glfwWindow = window,
            .input = in.Input.init(window),
        };
    }

    pub fn deinit(self: *const Window) void {
        c.glfwDestroyWindow(self.glfwWindow);
    }

    pub fn pollEvents(self: *Window) void {
        c.glfwPollEvents();
        in.updateInput(&self.input);
    }

    pub fn shouldClose(self: *const Window) bool {
        return c.glfwWindowShouldClose(self.glfwWindow) == c.GLFW_TRUE;
    }

    pub fn getVulkanContext(
        self: *Window,
        allocator: std.mem.Allocator,
    ) !vulkan.context.VulkanContext {
        const platform = c.glfwGetPlatform();

        if (platform == c.GLFW_PLATFORM_WAYLAND) {
            self.pollEvents();
        }

        var width: c_int = undefined;
        var height: c_int = undefined;
        c.glfwGetWindowSize(self.glfwWindow, &width, &height);

        switch (platform) {
            c.GLFW_PLATFORM_WAYLAND => {
                const display = c.glfwGetWaylandDisplay() orelse
                    @panic("Could not get wayland display");
                const surface = c.glfwGetWaylandWindow(self.glfwWindow) orelse
                    @panic("could not get wayland window");
                return try vulkan.context.VulkanContext.init(
                    .{
                        .display = @ptrCast(display),
                        .surface = @ptrCast(surface),
                    },
                    @intCast(width),
                    @intCast(height),
                    allocator,
                );
            },
            else => @panic("Unsupported platform"),
        }
    }
};
