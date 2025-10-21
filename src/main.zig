const std = @import("std");

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

pub fn main() !void {
    const window = createMacWindow() orelse return error.WindowCreationFailed;
    defer releaseMacWindow(window);

    std.debug.print("Window created! Close it or press keys to see events.\n", .{});

    var event: MacEvent = undefined;
    while (pollMacEvent(&event)) {
        switch (event.type) {
            .key_down => {
                std.debug.print("Key down: {}\n", .{event.key_code});
            },
            .key_up => {
                std.debug.print("Key up: {}\n", .{event.key_code});
            },
            .mouse_down => {
                std.debug.print("Mouse down at: {d:.1}, {d:.1}\n", .{ event.mouse_x, event.mouse_y });
            },
            .mouse_moved => {
                std.debug.print("Mouse moved to: {d:.1}, {d:.1}\n", .{ event.mouse_x, event.mouse_y });
            },
            .scroll_wheel => {
                std.debug.print("Scroll: {d:.1}, {d:.1}\n", .{ event.delta_x, event.delta_y });
            },
            .none => {},
            else => {},
        }

        std.Thread.sleep(50000);
    }

    std.debug.print("Window closed, exiting.\n", .{});
}
