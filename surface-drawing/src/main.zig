const std = @import("std");
const w = @import("window");
const Window = w.Window;
const vulkan = @import("vulkan");
const RoundedRectanglePipeline = @import("RoundedRectanglePipeline.zig").RoundedCornerPipeline;
const Ui = @import("ui");
const math = @import("math");

const Context = struct {
    pipeline: RoundedRectanglePipeline,
    cmd: ?vulkan.vk.c.VkCommandBuffer,
    resolution: math.Vec2,
};

fn drawRect(
    context: *Context,
    rect: Ui.Rect,
    r: f32,
    border: f32,
    color: Ui.Color,
    borderColor: Ui.Color,
    _: ?Ui.Rect,
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

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    var window = Window.init(1920, 1280);
    defer window.deinit();

    var context = try window.getVulkanContext(allocator);

    var roundedRectanglePipeline = try RoundedRectanglePipeline.init(context);
    defer roundedRectanglePipeline.deinit();

    var x: f32 = 50;
    var y: f32 = 50;

    var uiContext = Context{
        .cmd = null,
        .pipeline = roundedRectanglePipeline,
        .resolution = math.Vec2.init(.{ @floatFromInt(context.width), @floatFromInt(context.height) }),
    };
    var ui = Ui.Ui(Context, .{ .drawRect = drawRect }).init(allocator, &uiContext);

    while (!window.shouldClose()) {
        for (window.pollEvents()) |event| {
            switch (event) {
                w.Event.TouchEvent => |pos| {
                    x = pos.x();
                    y = pos.y();
                    std.debug.print("Processed event: ({},{})\n", .{ x, y });
                },
                else => {},
            }
        }
        const cmd = try context.beginDraw();
        uiContext.cmd = cmd;

        x += 0;
        y += 0;

        ui.drawRect(.{ .h = 50, .w = 50, .x = x, .y = y }, .{ 1, 0, 0, 1 }, 5, .{ 0, 1, 0, 1 }, 4);

        uiContext.cmd = null;
        try context.endDraw();
    }
}
