const std = @import("std");
const glfw = @import("glfw.zig");
const c = glfw.c;
const vulkan = @import("vulkan");
const vk = vulkan.vk.c;
const in = @import("input.zig");

// GLFW's Vulkan helpers are not part of glfw.zig's @cImport (it doesn't pull in
// the Vulkan headers), so declare them here against the vulkan module's types.
// This also keeps the handle types identical to those VulkanContext expects.
extern fn glfwCreateWindowSurface(
    instance: vk.VkInstance,
    window: ?*c.struct_GLFWwindow,
    allocator: ?*const vk.VkAllocationCallbacks,
    surface: *vk.VkSurfaceKHR,
) vk.VkResult;
extern fn glfwInitVulkanLoader(loader: vk.PFN_vkGetInstanceProcAddr) void;

pub const Window = struct {
    glfwWindow: *c.struct_GLFWwindow,
    input: in.Input,

    pub fn init(width: u32, height: u32) Window {
        // Point GLFW at the directly-linked Vulkan implementation (MoltenVK on
        // macOS) so it doesn't have to dlopen a separate loader at runtime.
        // Must happen before glfwInit.
        glfwInitVulkanLoader(vk.vkGetInstanceProcAddr);

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
        // Framebuffer size is in pixels (unlike window size, which is in logical
        // points on HiDPI). It's only a fallback: on surfaces with a fixed
        // extent (macOS) the context uses the surface's currentExtent instead.
        var width: c_int = undefined;
        var height: c_int = undefined;
        c.glfwGetFramebufferSize(self.glfwWindow, &width, &height);

        // Let GLFW create the platform surface (Wayland on Linux, Metal/Cocoa
        // on macOS). The instance is created here so we can hand both to the
        // context.
        const instance = try vulkan.instance.createInstance(.{ .name = "Testbed" });

        var surface: vk.VkSurfaceKHR = null;
        const result = glfwCreateWindowSurface(instance, self.glfwWindow, null, &surface);
        if (result != vk.VK_SUCCESS) {
            std.log.err("glfwCreateWindowSurface failed: {d}", .{result});
            return error.SurfaceCreationFailed;
        }

        return try vulkan.context.VulkanContext.initWithSurface(
            instance,
            surface,
            @intCast(width),
            @intCast(height),
            allocator,
        );
    }
};
