pub const EventType = enum(c_int) {
    none = 0,
    mouse_down = 1,
    mouse_up = 2,
    mouse_moved = 5,
    key_down = 10,
    key_up = 11,
    scroll_wheel = 22,
    _,
};

pub const MacEvent = extern struct {
    type: EventType,
    key_code: u16,
    mouse_x: f64,
    mouse_y: f64,
    delta_x: f64,
    delta_y: f64,
};

pub extern fn createMacWindow() ?*anyopaque;
pub extern fn pollMacEvent(event: *MacEvent) bool;
pub extern fn releaseMacWindow(?*anyopaque) void;
pub extern fn getMetalLayer(window: *anyopaque) *anyopaque;
pub extern fn getWindowSize(window: *anyopaque, width: *c_int, height: *c_int) void;
