const std = @import("std");
const Window = @import("window").Window;
const vulkan = @import("vulkan");
const c = vulkan.vk.c;
const RoundedRectanglePipeline = @import("RoundedRectanglePipeline.zig").RoundedCornerPipeline;
const Ui = @import("ui");
const math = @import("math");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    var window = Window.init(500, 500);
    defer window.deinit();

    var context = try window.getVulkanContext(allocator);

    var roundedRectanglePipeline = try RoundedRectanglePipeline.init(context);
    defer roundedRectanglePipeline.deinit();

    var uiContext = Context{
        .cmd = null,
        .pipeline = roundedRectanglePipeline,
        .resolution = math.Vec2.zero,
    };
    var ui = Ui.Ui(Context, .{ .drawRect = drawRect }).init(allocator, &uiContext);

    while (!window.shouldClose()) {
        if (window.input.down(.ESCAPE)) {
            break;
        }

        const command = try context.beginDraw();
        const width, const height = window.getSize();
        uiContext.cmd = command;
        uiContext.resolution = math.Vec2.init(.{ @as(f32, @floatFromInt(width)), @as(f32, @floatFromInt(height)) });
        const style = Ui.Style{
            .border = .{
                .color = .{ 0.3, 0.3, 0.3, 1 },
                .width = 3,
            },
            .color = .{ 0.4, 0.4, 0.4, 1 },
        };
        ui.drawRect(.{
            .rect = .{
                .x = 20,
                .y = 20,
                .w = 30,
                .h = 30,
            },
            .style = style,
        });

        try context.endDraw();
        window.pollEvents();
    }
}

const Context = struct {
    pipeline: RoundedRectanglePipeline,
    cmd: ?c.VkCommandBuffer,
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
