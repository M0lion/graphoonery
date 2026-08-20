const ui = @import("ui");
const RoundedRectanglePipeline = @import("RoundedRectanglePipeline.zig").RoundedCornerPipeline;
const vulkan = @import("vulkan");
const math = @import("math");

pub const Ui = ui.Ui(Context, .{ .drawRect = drawRect });

pub const Context = struct {
    pipeline: RoundedRectanglePipeline,
    cmd: ?vulkan.vk.c.VkCommandBuffer,
    resolution: math.Vec2,
};

fn drawRect(
    context: *Context,
    rect: ui.Rect,
    r: f32,
    border: f32,
    color: ui.Color,
    borderColor: ui.Color,
    _: ?ui.Rect,
) void {
    context.pipeline.draw(context.cmd.?, .{
        .border = border,
        .border_color = math.Vec4.init(.{ borderColor[0], borderColor[1], borderColor[2], borderColor[3] }),
        .center = math.Vec2.init(.{ rect.x + (rect.w / 2), rect.y + (rect.h / 2) }),
        .fill = math.Vec4.init(.{ color[0], color[1], color[2], color[3] }),
        .half_size = math.Vec2.init(.{ rect.w / 2, rect.h / 2 }),
        .radius = r,
        .resolution = context.resolution,
    }) catch @panic("fail draw");
}
