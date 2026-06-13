const std = @import("std");
const fontstash = @import("fontstash.zig");

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const Color = [4]f32;

pub const InputData = struct {
    hovered: bool,
    clicked: bool,
    focus: bool,
};

pub const BorderDescription = struct {
    width: f32,
    color: Color,
};

pub const IdDescription = struct {
    src: std.builtin.SourceLocation,
    id: []const u8,
};

pub const RectDescription = struct {
    rect: Rect,
    style: Style,
    scissor: ?Rect = null,
    src: ?std.builtin.SourceLocation = null,
};

pub const Style = struct {
    color: Color,
    border: ?BorderDescription = null,
    r: f32 = 0,
};

pub fn Backend(comptime Context: type) type {
    return struct {
        drawRect: fn (context: *Context, rect: Rect, r: f32, border: f32, color: Color, borderColor: Color, scissor: ?Rect) void,
    };
}

pub fn Ui(comptime Context: type, comptime backend: Backend(Context)) type {
    return struct {
        const Self = @This();

        context: *Context,
        allocator: std.heap.ArenaAllocator,
        fontRenderer: fontstash.FontRenderer,

        pub fn init(allocator: std.mem.Allocator, context: *Context) Self {
            return .{
                .context = context,
                .allocator = std.heap.ArenaAllocator.init(allocator),
                .fontRenderer = fontstash.FontRenderer.init(allocator, .{}),
            };
        }

        pub fn update(self: *Self) void {
            self.allocator.reset(.free_all);
        }

        pub fn drawRect(self: *Self, rect: RectDescription) void {
            const border = rect.style.border orelse BorderDescription{
                .color = rect.style.color,
                .width = 0,
            };
            fontstash.FontRenderer.drawText("foo");
            backend.drawRect(
                self.context,
                rect.rect,
                rect.style.r,
                border.width,
                rect.style.color,
                border.color,
                rect.scissor,
            );
        }

        pub fn deinit(self: *Self) void {
            self.allocator.deinit();
        }
    };
}

pub const Direction = enum {
    Horizontal,
    Vertical,
};

pub const FlexLayout = struct {
    direction: Direction,
    length: ?f32,
};
