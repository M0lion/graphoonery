const std = @import("std");
const c = @import("glfw.zig").c;
const k = @import("keys.zig");

pub const Input = struct {
    window: *c.struct_GLFWwindow,
    keys: std.enums.EnumArray(k.Key, k.KeyState),

    pub const Key = k.Key;

    pub fn init(window: *c.struct_GLFWwindow) Input {
        var keys = std.enums.EnumArray(k.Key, k.KeyState).initUndefined();

        var iter = keys.iterator();
        while (iter.next()) |entry| {
            const keyToken = k.getGlfwKeyTokenFromKey(entry.key);
            if (c.glfwGetKey(window, keyToken) == c.GLFW_PRESS) {
                entry.value.* = .Down;
            } else {
                entry.value.* = .Up;
            }
        }

        return Input{
            .window = window,
            .keys = keys,
        };
    }

    pub fn down(self: *Input, key: Key) bool {
        const state = self.keys.get(key);
        return state == .Down or state == .Pressed;
    }

    pub fn up(self: *Input, key: Key) bool {
        const state = self.keys.get(key);
        return state == .Up or state == .Released;
    }

    pub fn pressed(self: *Input, key: Key) bool {
        const state = self.keys.get(key);
        return state == .Pressed;
    }

    pub fn released(self: *Input, key: Key) bool {
        const state = self.keys.get(key);
        return state == .Released;
    }
};

pub fn updateInput(input: *Input) void {
    var iter = input.keys.iterator();
    while (iter.next()) |entry| {
        const keyToken = k.getGlfwKeyTokenFromKey(entry.key);
        if (c.glfwGetKey(input.window, keyToken) == c.GLFW_PRESS) {
            entry.value.* = switch (entry.value.*) {
                .Down => .Down,
                .Up => .Pressed,
                .Pressed => .Down,
                .Released => .Pressed,
            };
        } else {
            entry.value.* = switch (entry.value.*) {
                .Down => .Released,
                .Up => .Up,
                .Pressed => .Released,
                .Released => .Up,
            };
        }
    }
}
