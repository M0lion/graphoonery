const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("string.h");
    @cInclude("stdlib.h");
    @cDefine("FONTSTASH_IMPLEMENTATION", "");
    @cInclude("fontstash.h");
});

pub const FontRenderer = struct {
    fonsParams: *c.FONSparams,
    fonsContext: *c.FONScontext,
    fontNormal: c_int,

    pub fn init(allocator: std.mem.Allocator, params: c.FONSparams) !FontRenderer {
        const fonsParams = try allocator.create(c.FONSparams);
        fonsParams = params;
        const fonsContext = c.fonsCreateInternal(fonsParams);

        const fontNormal = c.fonsAddFont(fonsContext, "sans", "/usr/share/fonts/TTF/HackNerdFontMono-Regular.ttf");
        c.fonsSetFont(fonsContext, fontNormal);

        return FontRenderer{
            .fonsParams = fonsParams,
            .fonsContext = fonsContext,
            .fontNormal = fontNormal,
        };
    }

    pub fn drawText(text: []const u8) void {
        std.log.debug("Foo: {s}", .{text});
    }
};
