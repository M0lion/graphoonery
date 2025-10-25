const builtin = @import("builtin");

pub const Platform = enum {
    macos,
    linux,
};
pub const platform = if (builtin.os.tag == .macos) Platform.macos else Platform.linux;
