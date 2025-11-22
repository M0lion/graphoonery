const std = @import("std");
const w = @import("wayland_c.zig");
const c = w.c;
const WaylandWindow = @import("wayland.zig").WaylandWindow;

pub const Seat = struct {
    keyboardState: KeyboardState = undefined,
    keyboard: ?*c.wl_keyboard = undefined,

    keyHandler: ?*const fn (c_uint) void = null,
    keyStringHandler: ?*const fn ([]u8) void = null,

    pub fn init(self: *Seat, seat: *c.wl_seat) !void {
        self.keyboardState = KeyboardState{};
        try w.checkResult(c.wl_seat_add_listener(seat, &seatBaseListener, self));
    }

    pub fn deinit(self: *Seat) void {
        if (self.keyboard) |keyboard| {
            c.wl_keyboard_destroy(keyboard);
        }
    }
};

pub const seatBaseListener = c.wl_seat_listener{
    .capabilities = seatCapabilities,
    .name = seatName,
};

fn seatCapabilities(data: ?*anyopaque, wlSeat: ?*c.wl_seat, capabilities: c.enum_wl_seat_capability) callconv(.c) void {
    const seat = @as(?*Seat, @ptrCast(@alignCast(data))) orelse @panic("keyboardKeyListener is null");
    std.log.debug("CAPABILITIES", .{});
    if (capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD != 0) {
        seat.keyboard = c.wl_seat_get_keyboard(wlSeat);
        _ = c.wl_keyboard_add_listener(seat.keyboard, &keyboardBaseListener, data);
    }
}

fn seatName(
    _: ?*anyopaque,
    _: ?*c.wl_seat,
    name: [*c]const u8,
) callconv(.c) void {
    std.log.debug("Seat Name: {s}", .{name});
}

// State to track keyboard context
const KeyboardState = struct {
    xkb_context: ?*c.xkb_context = null,
    xkb_keymap: ?*c.xkb_keymap = null,
    xkb_state: ?*c.xkb_state = null,
    compose_table: ?*c.xkb_compose_table = null,
    compose_state: ?*c.xkb_compose_state = null,
};

const keyboardBaseListener = c.wl_keyboard_listener{
    .keymap = keyboardKeymapListener,
    .enter = keyboardEnterListener,
    .leave = keyboardLeaveListener,
    .key = keyboardKeyListener,
    .modifiers = keyboardModifiersListener,
    .repeat_info = keyboardRepeatInfoListener,
};

fn keyboardKeymapListener(
    data: ?*anyopaque,
    _: ?*c.wl_keyboard,
    format: c.enum_wl_keyboard_keymap_format,
    fd: i32,
    size: u32,
) callconv(.c) void {
    const seat = @as(?*Seat, @ptrCast(@alignCast(data))) orelse @panic("keyboardKeyListener is null");
    if (format != c.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
        std.posix.close(fd);
        return;
    }

    // Create xkb context if needed
    if (seat.keyboardState.xkb_context == null) {
        seat.keyboardState.xkb_context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
    }

    // Memory map the keymap
    const map_data = std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ,
        .{ .TYPE = .PRIVATE },
        fd,
        0,
    ) catch {
        std.posix.close(fd);
        return;
    };
    defer std.posix.munmap(map_data);
    std.posix.close(fd);

    // Create keymap from string
    seat.keyboardState.xkb_keymap = c.xkb_keymap_new_from_string(
        seat.keyboardState.xkb_context,
        @ptrCast(map_data.ptr),
        c.XKB_KEYMAP_FORMAT_TEXT_V1,
        c.XKB_KEYMAP_COMPILE_NO_FLAGS,
    );

    // Create xkb state
    if (seat.keyboardState.xkb_state) |state| {
        c.xkb_state_unref(state);
    }
    seat.keyboardState.xkb_state = c.xkb_state_new(seat.keyboardState.xkb_keymap);

    // Setup compose table for dead keys
    if (seat.keyboardState.xkb_context) |ctx| {
        // Get locale from environment
        const locale = std.posix.getenv("LC_ALL") orelse
            std.posix.getenv("LC_CTYPE") orelse
            std.posix.getenv("LANG") orelse
            "C";

        seat.keyboardState.compose_table = c.xkb_compose_table_new_from_locale(
            ctx,
            locale.ptr,
            c.XKB_COMPOSE_COMPILE_NO_FLAGS,
        );

        if (seat.keyboardState.compose_state) |state| {
            c.xkb_compose_state_unref(state);
        }

        if (seat.keyboardState.compose_table) |table| {
            seat.keyboardState.compose_state = c.xkb_compose_state_new(
                table,
                c.XKB_COMPOSE_STATE_NO_FLAGS,
            );
        }
    }
}

fn keyboardEnterListener(
    _: ?*anyopaque,
    _: ?*c.wl_keyboard,
    serial: c_uint,
    surface: ?*c.wl_surface,
    keys: ?*c.wl_array,
) callconv(.c) void {
    _ = serial;
    _ = surface;
    _ = keys;
    std.log.debug("Keyboard focus gained", .{});
}

fn keyboardLeaveListener(
    _: ?*anyopaque,
    _: ?*c.wl_keyboard,
    serial: c_uint,
    surface: ?*c.wl_surface,
) callconv(.c) void {
    _ = serial;
    _ = surface;
    std.log.debug("Keyboard focus lost", .{});
}

fn keyboardKeyListener(
    data: ?*anyopaque,
    _: ?*c.wl_keyboard,
    serial: c_uint,
    time: c_uint,
    key: c_uint,
    state: c.wl_keyboard_key_state,
) callconv(.c) void {
    _ = serial;
    _ = time;
    const seat = @as(?*Seat, @ptrCast(@alignCast(data))) orelse @panic("keyboardKeyListener is null");

    const pressed = state == c.WL_KEYBOARD_KEY_STATE_PRESSED;

    // Only process key presses for compose
    if (!pressed) {
        return;
    }

    if (seat.keyboardState.xkb_state) |xkb_state| {
        if (seat.keyHandler) |keyHandler| {
            keyHandler(key);
        }

        // Wayland keycode is evdev keycode + 8
        const xkb_keycode = key + 8;
        const keysym = c.xkb_state_key_get_one_sym(xkb_state, xkb_keycode);

        // Try to handle compose sequences (dead keys)
        if (seat.keyboardState.compose_state) |compose_state| {
            const feed_result = c.xkb_compose_state_feed(compose_state, keysym);

            if (feed_result == c.XKB_COMPOSE_FEED_ACCEPTED) {
                const status = c.xkb_compose_state_get_status(compose_state);

                switch (status) {
                    c.XKB_COMPOSE_COMPOSING => {
                        return;
                    },
                    c.XKB_COMPOSE_COMPOSED => {
                        // Get the composed character
                        const composed_sym = c.xkb_compose_state_get_one_sym(compose_state);

                        // Convert to UTF-8
                        var buf: [32]u8 = undefined;
                        const len = c.xkb_keysym_to_utf8(composed_sym, &buf, buf.len);

                        if (len > 0) {
                            const utf8_char = buf[0..@intCast(len - 1)]; // -1 to exclude null terminator
                            if (seat.keyStringHandler) |keyStringHandler| {
                                keyStringHandler(utf8_char);
                            }
                        }

                        // Reset compose state for next sequence
                        c.xkb_compose_state_reset(compose_state);
                        return;
                    },
                    c.XKB_COMPOSE_CANCELLED => {
                        std.log.debug("Compose cancelled", .{});
                        c.xkb_compose_state_reset(compose_state);
                        // Fall through to handle as regular key
                    },
                    c.XKB_COMPOSE_NOTHING => {
                        // Not part of a compose sequence, handle as regular key
                    },
                    else => {},
                }
            }
        }

        // Handle as regular key (no compose or compose not applicable)
        var name_buf: [64]u8 = undefined;
        _ = c.xkb_keysym_get_name(keysym, &name_buf, name_buf.len);

        // Get UTF-8 character
        var utf8_buf: [32]u8 = undefined;
        const utf8_len = c.xkb_state_key_get_utf8(xkb_state, xkb_keycode, &utf8_buf, utf8_buf.len);

        if (utf8_len > 0) {
            const utf8_char = utf8_buf[0..@intCast(utf8_len)];
            if (seat.keyStringHandler) |keyStringHandler| {
                keyStringHandler(utf8_char);
            }
        }
    }
}

fn keyboardModifiersListener(
    data: ?*anyopaque,
    _: ?*c.wl_keyboard,
    serial: c_uint,
    mods_depressed: c_uint,
    mods_latched: c_uint,
    mods_locked: c_uint,
    group: c_uint,
) callconv(.c) void {
    const seat = @as(?*Seat, @ptrCast(@alignCast(data))) orelse @panic("keyboardKeyListener is null");
    _ = serial;

    if (seat.keyboardState.xkb_state) |xkb_state| {
        _ = c.xkb_state_update_mask(
            xkb_state,
            mods_depressed,
            mods_latched,
            mods_locked,
            0,
            0,
            group,
        );
    }
}

fn keyboardRepeatInfoListener(
    _: ?*anyopaque,
    _: ?*c.wl_keyboard,
    rate: i32,
    delay: i32,
) callconv(.c) void {
    std.log.debug("Repeat rate: {}, delay: {}", .{ rate, delay });
}
