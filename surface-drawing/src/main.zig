const std = @import("std");
const w = @import("window");
const Window = w.Window;
const vulkan = @import("vulkan");
const RoundedRectanglePipeline = @import("RoundedRectanglePipeline.zig").RoundedCornerPipeline;
const DrawingPipeline = @import("DrawingPipeline.zig").DrawingPipeline;
const Ui = @import("ui");
const math = @import("math");
const rp = vulkan.renderPass;

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
    _ = Window.hideCursor();

    var context = try window.getVulkanContext(allocator);

    var roundedRectanglePipeline = try RoundedRectanglePipeline.init(context, .{
        .renderPass = context.swapchainRenderPass,
    });
    defer roundedRectanglePipeline.deinit();

    const canvasRenderPass = try rp.createRenderPass(
        context.logicalDevice,
        .{
            .colorAttachment = .{
                .format = context.swapchainImageFormat,
                .initialLayout = vulkan.images.ImageLayout.ShaderReadOnlyOptimal,
                .finalLayout = vulkan.images.ImageLayout.ShaderReadOnlyOptimal,
                .loadOp = rp.AttachmentLoadOp.Load,
                .storeOp = rp.AttachmentStoreOp.Store,
                .stenciilLoadOp = rp.AttachmentLoadOp.DontCare,
                .stencilStoreOp = rp.AttachmentStoreOp.DontCare,
                .sampleCount = rp.SampleCount.Count_1,
            },
        },
    );

    var drawingPipeline = try DrawingPipeline.init(context, .{
        .renderPass = canvasRenderPass,
    });
    defer drawingPipeline.deinit();

    const drawingImage = try vulkan.images.createImage(
        context.logicalDevice,
        context.physicalDevice,
        .{
            .width = window.width,
            .height = window.height,
            .format = context.swapchainImageFormat,
            .initialLayout = vulkan.images.ImageLayout.Undefined,
            .usage = vulkan.vk.c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | vulkan.vk.c.VK_IMAGE_USAGE_SAMPLED_BIT,
        },
    );

    const attachments = [_]vulkan.vk.c.VkImageView{
        drawingImage.imageView,
    };

    const drawingBuffer = try vulkan.framebuffer.createFramebuffer(
        context.logicalDevice,
        attachments[0..],
        drawingPipeline.renderPass,
        window.width,
        window.height,
    );

    var x: f32 = 500;
    var y: f32 = 500;

    var uiContext = Context{
        .cmd = null,
        .pipeline = roundedRectanglePipeline,
        .resolution = math.Vec2.init(.{ @floatFromInt(context.width), @floatFromInt(context.height) }),
    };
    var ui = Ui.Ui(Context, .{ .drawRect = drawRect }).init(allocator, &uiContext);

    var draw: bool = false;
    while (!window.shouldClose()) {
        for (window.pollEvents()) |event| {
            switch (event) {
                w.Event.Touch, w.Event.Click, w.Event.TouchMove => |pos| {
                    x = pos.x();
                    y = pos.y();
                    std.debug.print("Processed event: ({},{})\n", .{ x, y });
                    draw = true;
                },
                else => {},
            }
        }
        const cmd = try context.beginDraw();
        try context.acquireSwapchain();
        const clearColor = [_]vulkan.vk.c.VkClearValue{
            vulkan.vk.c.VkClearValue{ .color = .{ .float32 = [_]f32{ 0.0, 0.31, 0.8, 1.0 } } },
            vulkan.vk.c.VkClearValue{ .depthStencil = .{ .depth = 1, .stencil = 0 } },
        };
        try context.beginPass(
            .{
                .cmd = cmd,
                .renderPass = drawingPipeline.renderPass,
                .clearValues = clearColor[0..],
                .extent = .{
                    .width = window.width,
                    .height = window.height,
                },
                .framebuffer = drawingBuffer,
            },
        );
        try drawingPipeline.draw(cmd, .{
            .center = math.Vec2.init(.{ x, y }),
            .fill = math.Vec4.init(.{ 1, 1, 1, 1 }),
            .radius = 50,
            .resolution = math.Vec2.init(.{ 1920, 1280 }),
        });
        context.endPass();
        try context.beginSwapchainPass(.{ .cmd = cmd });
        uiContext.cmd = cmd;

        ui.drawRect(.{ .h = 50, .w = 50, .x = 0, .y = 0 }, .{ 1, 0, 0, 1 }, 5, .{ 0, 1, 0, 1 }, 4);

        uiContext.cmd = null;

        context.endSwapchainPass();
        try context.endDraw();
        try context.presentSwpachain();
    }
}
