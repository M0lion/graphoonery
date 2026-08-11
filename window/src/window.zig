const std = @import("std");
const glfw = @import("glfw.zig");
const vulkan = @import("vulkan");
const vk = vulkan.vk.c;
const in = @import("input.zig");
const c = @import("sdl.zig").c;
const math = @import("math");
const keys = @import("keys.zig");

pub const EventType = enum {
    TouchEvent,
    ClickEvent,
    KeyDownEvent,
};

pub const Event = union(EventType) {
    TouchEvent: math.Vec2,
    ClickEvent: math.Vec2,
    KeyDownEvent: keys.Key,
};

pub const Window = struct {
    window: *c.struct_SDL_Window,
    input: in.Input,
    windowShouldClose: bool = false,

    pub fn init(width: u32, height: u32) Window {
        c.SDL_SetHint(c.SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
            @panic("foo");
        }

        const window = c.SDL_CreateWindow("hello", @intCast(width), @intCast(height), 0) orelse
            @panic("Could not create window");

        const input = in.Input.init(window);

        return Window{
            .window = window,
            .input = input,
        };
    }

    pub fn deinit(self: *const Window) void {
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    pub fn hideCursor() bool {
        return c.SDL_HideCursor();
    }

    pub fn pollEvents(self: *Window) []Event {
        var event: c.SDL_Event = undefined;
        var events: [64]Event = undefined;
        var eventCount: usize = 0;
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_KEY_DOWN => {
                    const name = c.SDL_GetKeyName(event.key.key);
                    std.debug.print("Keycode: {s}\nScanCode: {x}\n", .{ name, event.key.scancode });
                    if (event.key.scancode == c.SDL_SCANCODE_ESCAPE) {
                        self.windowShouldClose = true;
                        continue;
                    }
                    events[eventCount] = Event{
                        .KeyDownEvent = keys.getKeyFromSdlScancode(event.key.scancode),
                    };
                    eventCount += 1;
                },
                c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                    self.windowShouldClose = true;
                    continue;
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    events[eventCount] = Event{ .ClickEvent = math.Vec2.init(
                        .{
                            event.button.x - 25,
                            event.button.y - 25,
                        },
                    ) };
                    eventCount += 1;
                },
                c.SDL_EVENT_FINGER_DOWN => {
                    var width: c_int = 0;
                    var height: c_int = 0;
                    if (!c.SDL_GetWindowSize(self.window, &width, &height)) {
                        @panic("Could not get window size");
                    }
                    std.debug.print("Raw FINGER_DOWN: ({},{}) - ({},{})\n", .{ event.tfinger.x, event.tfinger.y, width, height });
                    events[eventCount] = Event{ .TouchEvent = math.Vec2.init(
                        .{
                            (event.tfinger.x * @as(f32, @floatFromInt(width))) - 25,
                            (event.tfinger.y * @as(f32, @floatFromInt(height))) - 25,
                        },
                    ) };
                    eventCount += 1;
                },
                else => {
                    std.debug.print("{}\n", .{event.type});
                },
            }
        }

        return events[0..eventCount];
    }

    pub fn shouldClose(self: *const Window) bool {
        return self.windowShouldClose;
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
        if (!c.SDL_GetWindowSize(self.window, &width, &height)) @panic("Failed to get window size");

        var extensionCount: c_uint = 0;
        const extensions = c.SDL_Vulkan_GetInstanceExtensions(&extensionCount) orelse
            @panic("could not get sdl vulkan extensions");

        const instance = try vulkan.instance.createInstance(.{ .name = "Testbed" }, extensions[0..extensionCount]);

        var surface: vk.VkSurfaceKHR = null;
        if (!c.SDL_Vulkan_CreateSurface(self.window, @ptrCast(instance), null, &surface)) {
            std.log.err("sdl surface creation failed", .{});
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
