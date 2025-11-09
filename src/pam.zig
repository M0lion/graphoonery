const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("security/pam_appl.h");
});
fn conv_callback(
    num_msg: c_int,
    msg: [*c][*c]const c.struct_pam_message,
    response: [*c][*c]c.struct_pam_response,
    appdata_ptr: ?*anyopaque,
) callconv(.c) c_int {
    const appdata: ?*const Appdata = @ptrCast(@alignCast(appdata_ptr));

    // Allocate the response array
    const responses: [*c]c.struct_pam_response = @ptrCast(@alignCast(
        c.calloc(@intCast(num_msg), @sizeOf(c.struct_pam_response))
    ));
    if (responses == null) {
        return c.PAM_BUF_ERR;
    }
    response.* = responses;

    for (0..@intCast(num_msg)) |i| {
        if (msg[i].*.msg_style == c.PAM_PROMPT_ECHO_OFF) {
            // Use strdup so PAM can properly free the memory with free()
            responses[i].resp = c.strdup(appdata.?.password.ptr);
            responses[i].resp_retcode = 0;
        }
    }

    return c.PAM_SUCCESS;
}

const Appdata = struct {
    password: []const u8,
    allocator: std.mem.Allocator,
};

pub fn authenticate(allocator: std.mem.Allocator, password: []const u8) bool {
    var appdata = Appdata{
        .allocator = allocator,
        .password = password,
    };

    var pam_handle: ?*c.pam_handle = null;
    var pam_conv = c.pam_conv{
        .appdata_ptr = &appdata,
        .conv = conv_callback,
    };

    _ = c.pam_start("login", "bjorn", &pam_conv, &pam_handle);
    const result = c.pam_authenticate(pam_handle, 0);
    if (result == c.PAM_SUCCESS) {
        std.log.debug("Success", .{});
        _ = c.pam_end(pam_handle, result);
        return true;
    } else {
        std.log.debug("Fail", .{});
        _ = c.pam_end(pam_handle, result);
        return false;
    }

    return true;
}
