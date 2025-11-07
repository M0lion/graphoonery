const c = @cImport({
    @cInclude("macos_types.h");
});

pub extern fn createMacWindow() ?*anyopaque;
pub extern fn pollMacEvent(event: *c.MacEvent) bool;
pub extern fn releaseMacWindow(?*anyopaque) void;
pub extern fn getMetalLayer(window: *anyopaque) *anyopaque;
pub extern fn getWindowSize(window: *anyopaque, width: *c_int, height: *c_int) void;
