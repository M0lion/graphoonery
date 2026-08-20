const std = @import("std");
const Ui = @import("ui.zig").Ui;
const math = @import("math");
const IVec2 = math.IVec2;
const Vec4 = math.Vec4;

pub const ColorPickerConfig = struct {
    pos: IVec2,
    size: IVec2,
    colors: []const Vec4,
    picked: usize,
};

pub const MouseState = struct {
    pos: IVec2,
    clicked: bool,
};

pub fn drawColorPicker(ui: *Ui, mouseState: MouseState, config: ColorPickerConfig) usize {
    const radius = config.size.y();
    const hOffset = config.size.x() - radius;
    const halfRadius = @divFloor(config.size.y(), 2);
    const vOffset = halfRadius;
    const spacing = @divFloor(hOffset, @as(i32, @intCast(config.colors.len - 1)));
    var picked = config.picked;
    for (config.colors, 0..) |color, i| {
        const isPicked = config.picked == i;
        const borderColor: [4]f32 = if (isPicked) .{ 0, 0, 0, 1 } else .{ 1, 1, 1, 1 };
        const x: i32 = hOffset + (spacing * @as(i32, @intCast(i))) + config.pos.x();
        const y: i32 = vOffset + config.pos.y();
        ui.drawRect(
            .{
                .h = @floatFromInt(radius),
                .w = @floatFromInt(radius),
                .x = @floatFromInt(x),
                .y = @floatFromInt(y),
            },
            color.data,
            5,
            borderColor,
            @floatFromInt(halfRadius),
        );

        if (mouseState.clicked) {
            const distance = IVec2.init(.{ x, y }).sub(mouseState.pos).lengthSq();
            const rSq = radius * radius;
            std.debug.print("Dis, RSq: ({},{})\n", .{ distance, rSq });
            if (distance < rSq) {
                picked = i;
            }
        }
    }

    return picked;
}
