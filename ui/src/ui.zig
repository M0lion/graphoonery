const std = @import("std");
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

        pub fn init(allocator: std.mem.Allocator, context: *Context) Self {
            return .{
                .context = context,
                .allocator = std.heap.ArenaAllocator.init(allocator),
            };
        }

        pub fn drawRect(self: *Self, rect: Rect, color: Color, border: f32, borderColor: Color, r: f32) void {
            backend.drawRect(self.context, rect, r, border, color, borderColor, null);
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
