const std = @import("std");
pub const c = @cImport({
    @cInclude("wayland-client.h");
    @cInclude("xdg-shell-client-protocol.h");
    @cInclude("ext-session-lock-v1-client-protocol.h");
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xkbcommon/xkbcommon-compose.h");
});

pub fn checkResult(result: c_int) !void {
    if (result == 0) {
        return;
    }

    std.log.err("Wayland fail: {}", .{result});
    return error.WaylandError;
}
