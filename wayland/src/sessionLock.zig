const std = @import("std");
const w = @import("wayland_c.zig");
const c = w.c;
const wl = @import("waylandConnection.zig");
const WaylandConnection = wl.WaylandConnection;
const sf = @import("surface.zig");
const st = @import("seat.zig");

pub const SessionLock = struct {
    allocator: std.mem.Allocator = undefined,
    lock: *c.ext_session_lock_v1,
    seat: st.Seat = undefined,
    locked: bool = false,

    pub fn init(self: *SessionLock, connection: *WaylandConnection, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.locked = false;
        const wlSeat = connection.seat orelse return error.NoSeat;
        try self.seat.init(wlSeat);
        try connection.roundtrip();
        const lockManager = connection.lockscreenManager orelse return error.NoLockManager;
        self.lock = c.ext_session_lock_manager_v1_lock(lockManager) orelse return error.NoLock;
        try w.checkResult(c.ext_session_lock_v1_add_listener(self.lock, &sessionLockListener, self));

        try connection.roundtrip();
    }

    pub fn deinit(self: *SessionLock) void {
        // Clean up seat
        self.seat.deinit();

        // Unlock and destroy the session lock
        c.ext_session_lock_v1_unlock_and_destroy(self.lock);
    }
};

const sessionLockListener = c.ext_session_lock_v1_listener{
    .finished = sessionLockFinished,
    .locked = sessionLockLocked,
};

fn sessionLockLocked(data: ?*anyopaque, _: ?*c.ext_session_lock_v1) callconv(.c) void {
    const self = @as(*SessionLock, @ptrCast(@alignCast(data.?)));
    self.locked = true;
    std.log.debug("Locked", .{});
}

fn sessionLockFinished(_: ?*anyopaque, _: ?*c.ext_session_lock_v1) callconv(.c) void {
    std.log.debug("Finished", .{});
}
