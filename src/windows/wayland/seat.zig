const std = @import("std");
const c = @import("wayland_c.zig").c;
const WaylandWindow = @import("wayland.zig").WaylandWindow;

pub const seatBaseListener = c.wl_seat_listener{
    .capabilities = seatCapabilities,
};

fn seatCapabilities(data: ?*anyopaque, seat: ?*c.wl_seat, capabilities: c.enum_wl_seat_capability) callconv(.c) void {
    if (capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD != 0) {
        const keyboard = c.wl_seat_get_keyboard(seat);
        _ = c.wl_keyboard_add_listener(keyboard, &keyboardBaseListener, data);
    }
}

// State to track keyboard context
const KeyboardState = struct {
    xkb_context: ?*c.xkb_context,
    xkb_keymap: ?*c.xkb_keymap,
    xkb_state: ?*c.xkb_state,
    compose_table: ?*c.xkb_compose_table,
    compose_state: ?*c.xkb_compose_state,
};

var keyboard_state = KeyboardState{
    .xkb_context = null,
    .xkb_keymap = null,
    .xkb_state = null,
    .compose_table = null,
    .compose_state = null,
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
    _: ?*anyopaque,
    _: ?*c.wl_keyboard,
    format: c.enum_wl_keyboard_keymap_format,
    fd: i32,
    size: u32,
) callconv(.c) void {
    if (format != c.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
        std.posix.close(fd);
        return;
    }

    // Create xkb context if needed
    if (keyboard_state.xkb_context == null) {
        keyboard_state.xkb_context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
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
    keyboard_state.xkb_keymap = c.xkb_keymap_new_from_string(
        keyboard_state.xkb_context,
        @ptrCast(map_data.ptr),
        c.XKB_KEYMAP_FORMAT_TEXT_V1,
        c.XKB_KEYMAP_COMPILE_NO_FLAGS,
    );

    // Create xkb state
    if (keyboard_state.xkb_state) |state| {
        c.xkb_state_unref(state);
    }
    keyboard_state.xkb_state = c.xkb_state_new(keyboard_state.xkb_keymap);

    // Setup compose table for dead keys
    if (keyboard_state.xkb_context) |ctx| {
        // Get locale from environment
        const locale = std.posix.getenv("LC_ALL") orelse
            std.posix.getenv("LC_CTYPE") orelse
            std.posix.getenv("LANG") orelse
            "C";

        keyboard_state.compose_table = c.xkb_compose_table_new_from_locale(
            ctx,
            locale.ptr,
            c.XKB_COMPOSE_COMPILE_NO_FLAGS,
        );

        if (keyboard_state.compose_state) |state| {
            c.xkb_compose_state_unref(state);
        }

        if (keyboard_state.compose_table) |table| {
            keyboard_state.compose_state = c.xkb_compose_state_new(
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
    const window = @as(?*WaylandWindow, @ptrCast(@alignCast(data))) orelse @panic("keyboardKeyListener is null");

    const pressed = state == c.WL_KEYBOARD_KEY_STATE_PRESSED;

    // Only process key presses for compose
    if (!pressed) {
        std.log.debug("Key released", .{});
        return;
    }

    if (keyboard_state.xkb_state) |xkb_state| {
        if (window.key_handler) |key_handler| {
            key_handler(key);
        }

        // Wayland keycode is evdev keycode + 8
        const xkb_keycode = key + 8;
        const keysym = c.xkb_state_key_get_one_sym(xkb_state, xkb_keycode);

        // Try to handle compose sequences (dead keys)
        if (keyboard_state.compose_state) |compose_state| {
            const feed_result = c.xkb_compose_state_feed(compose_state, keysym);

            if (feed_result == c.XKB_COMPOSE_FEED_ACCEPTED) {
                const status = c.xkb_compose_state_get_status(compose_state);

                switch (status) {
                    c.XKB_COMPOSE_COMPOSING => {
                        std.log.debug("Dead key pressed, waiting for next key...", .{});
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
                            std.log.debug("Composed character: {s}", .{utf8_char});
                            if (window.key_string_handler) |key_string_handler| {
                                key_string_handler(utf8_char);
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
            if (window.key_string_handler) |key_string_handler| {
                key_string_handler(utf8_char);
            }
            std.log.debug("Key: {s} ('{s} - {}')", .{
                std.mem.sliceTo(&name_buf, 0),
                utf8_char,
                xkb_keycode,
            });
        } else {
            std.log.debug("Key: {s}", .{std.mem.sliceTo(&name_buf, 0)});
        }
    }
}

fn keyboardModifiersListener(
    _: ?*anyopaque,
    _: ?*c.wl_keyboard,
    serial: c_uint,
    mods_depressed: c_uint,
    mods_latched: c_uint,
    mods_locked: c_uint,
    group: c_uint,
) callconv(.c) void {
    _ = serial;

    if (keyboard_state.xkb_state) |xkb_state| {
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
