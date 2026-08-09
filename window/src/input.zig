const std = @import("std");
const c = @import("sdl.zig").c;
const k = @import("keys.zig");

pub const Input = struct {
    window: *c.SDL_Window,
    keys: std.enums.EnumArray(k.Key, k.KeyState),

    pub const Key = k.Key;

    pub fn init(window: *c.SDL_Window) Input {
        var keys = std.enums.EnumArray(k.Key, k.KeyState).initUndefined();
        const state = c.SDL_GetKeyboardState(null);

        var iter = keys.iterator();
        while (iter.next()) |entry| {
            const keyToken = k.getSdlScancodeFromKey(entry.key);
            if (state[keyToken]) {
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
        const keyToken = k.getSdlScancodeFromKey(entry.key);
        const state = c.SDL_GetKeyboardState(null);
        if (state[keyToken]) {
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
