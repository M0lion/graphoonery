const std = @import("std");
const w = @import("wayland_c.zig");
const c = w.c;
const wl = @import("waylandConnection.zig");
const WaylandConnection = wl.WaylandConnection;
const sf = @import("surface.zig");
const st = @import("seat.zig");

const Output = struct {
    wlOutput: *wl.Output,
    surface: sf.Surface,
    lockSurface: sf.LockSurface,
};

pub const SessionLock = struct {
    allocator: std.mem.Allocator = undefined,
    lock: *c.ext_session_lock_v1,
    outputs: std.ArrayList(*Output) = undefined,
    seat: st.Seat = undefined,

    pub fn init(self: *SessionLock, connection: *WaylandConnection, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        const wlSeat = connection.seat orelse return error.NoSeat;
        try self.seat.init(wlSeat);
        try connection.roundtrip();
        const lockManager = connection.lockscreenManager orelse return error.NoLockManager;
        const compositor = connection.compositor orelse return error.NoCompositor;
        self.lock = c.ext_session_lock_manager_v1_lock(lockManager) orelse return error.NoLock;
        try w.checkResult(c.ext_session_lock_v1_add_listener(self.lock, &sessionLockListener, self));

        self.outputs = try std.ArrayList(*Output).initCapacity(allocator, connection.outputs.items.len);

        for (connection.outputs.items) |wlOutput| {
            const output = try allocator.create(Output);
            output.wlOutput = wlOutput;
            try output.surface.init(compositor);
            try output.lockSurface.init(
                self.lock,
                output.surface.surface,
                output.wlOutput.output,
            );
            try self.outputs.append(allocator, output);
        }

        try connection.roundtrip();
    }

    pub fn deinit(self: *SessionLock) void {
        c.ext_session_lock_v1_destroy(self.lock);
    }
};

const sessionLockListener = c.ext_session_lock_v1_listener{
    .finished = sessionLockFinished,
    .locked = sessionLockLocked,
};

fn sessionLockLocked(_: ?*anyopaque, _: ?*c.ext_session_lock_v1) callconv(.c) void {
    std.log.debug("Locked", .{});
}

fn sessionLockFinished(_: ?*anyopaque, _: ?*c.ext_session_lock_v1) callconv(.c) void {
    std.log.debug("Finished", .{});
}
