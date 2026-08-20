const std = @import("std");
const glfw = @import("glfw.zig");
const vulkan = @import("vulkan");
const vk = vulkan.vk.c;
const in = @import("input.zig");
const c = @import("sdl.zig").c;
const math = @import("math");
const keys = @import("keys.zig");

pub const EventType = enum {
    Touch,
    TouchMove,
    MouseDown,
    MouseUp,
    MouseMove,
    KeyDown,
};

pub const Event = union(EventType) {
    Touch: math.Vec2,
    TouchMove: math.Vec2,
    MouseDown: math.Vec2,
    MouseUp: math.Vec2,
    MouseMove: math.Vec2,
    KeyDown: keys.Key,
};

pub const Window = struct {
    window: *c.struct_SDL_Window,
    input: in.Input,
    windowShouldClose: bool = false,
    width: u23,
    height: u32,

    pub fn init(width: u32, height: u32) Window {
        _ = c.SDL_SetHint(c.SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
        if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
            @panic("foo");
        }

        const window = c.SDL_CreateWindow("hello", @intCast(width), @intCast(height), 0) orelse
            @panic("Could not create window");

        const input = in.Input.init(window);

        return Window{
            .window = window,
            .input = input,
            .width = @intCast(width),
            .height = @intCast(height),
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
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetWindowSize(self.window, &width, &height)) {
            @panic("Could not get window size");
        }

        self.width = @intCast(width);
        self.height = @intCast(height);

        var e: c.SDL_Event = undefined;
        var events: [64]Event = undefined;
        var eventCount: usize = 0;
        while (c.SDL_PollEvent(&e)) {
            switch (e.type) {
                c.SDL_EVENT_KEY_DOWN => {
                    const name = c.SDL_GetKeyName(e.key.key);
                    std.debug.print("Keycode: {s}\nScanCode: {x}\n", .{ name, e.key.scancode });
                    if (e.key.scancode == c.SDL_SCANCODE_ESCAPE) {
                        self.windowShouldClose = true;
                        continue;
                    }
                    events[eventCount] = Event{
                        .KeyDown = keys.getKeyFromSdlScancode(e.key.scancode),
                    };
                    eventCount += 1;
                },
                c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                    self.windowShouldClose = true;
                    continue;
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    events[eventCount] = Event{ .MouseDown = math.Vec2.init(.{
                        e.button.x,
                        e.button.y,
                    }) };
                    eventCount += 1;
                },
                c.SDL_EVENT_MOUSE_BUTTON_UP => {
                    events[eventCount] = Event{ .MouseUp = math.Vec2.init(.{
                        e.button.x,
                        e.button.y,
                    }) };
                    eventCount += 1;
                },
                c.SDL_EVENT_MOUSE_MOTION => {
                    events[eventCount] = Event{ .MouseMove = math.Vec2.init(.{
                        e.button.x,
                        e.button.y,
                    }) };
                    eventCount += 1;
                },
                c.SDL_EVENT_FINGER_DOWN => {
                    std.debug.print("Raw FINGER_DOWN: ({},{}) - ({},{})\n", .{ e.tfinger.x, e.tfinger.y, width, height });
                    events[eventCount] = Event{ .Touch = math.Vec2.init(.{
                        (e.tfinger.x * @as(f32, @floatFromInt(width))),
                        (e.tfinger.y * @as(f32, @floatFromInt(height))),
                    }) };
                    eventCount += 1;
                },
                c.SDL_EVENT_FINGER_MOTION => {
                    events[eventCount] = Event{ .TouchMove = math.Vec2.init(.{
                        e.tfinger.x * @as(f32, @floatFromInt(width)),
                        e.tfinger.y * @as(f32, @floatFromInt(height)),
                    }) };
                    eventCount += 1;
                },
                else => {
                    std.debug.print("{}\n", .{e.type});
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
