const std = @import("std");
const w = @import("window");
const Window = w.Window;
const vulkan = @import("vulkan");
const RoundedRectanglePipeline = @import("RoundedRectanglePipeline.zig").RoundedCornerPipeline;
const DrawingPipeline = @import("DrawingPipeline.zig").DrawingPipeline;
const CanvasPipeline = @import("CanvasPipeline.zig").CanvasPipeline;
const Ui = @import("ui.zig");
const math = @import("math");
const rp = vulkan.renderPass;
const ColorPicker = @import("ColorPicker.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    var window = Window.init(1920, 1280);
    defer window.deinit();
    //_ = Window.hideCursor();

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

    var canvasPipeline = try CanvasPipeline.init(context, .{
        .renderPass = context.swapchainRenderPass,
    }, allocator);
    defer canvasPipeline.deinit();

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

    const canvasDescriptor = try canvasPipeline.createDescriptorSet(drawingImage);

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

    var uiContext = Ui.Context{
        .cmd = null,
        .pipeline = roundedRectanglePipeline,
        .resolution = math.Vec2.init(.{ @floatFromInt(context.width), @floatFromInt(context.height) }),
    };
    var ui = Ui.Ui.init(allocator, &uiContext);

    const colors = [_]math.Vec4{
        math.Vec4.init(.{ 0.0, 0.0, 0.0, 1.0 }), // black
        math.Vec4.init(.{ 1.0, 1.0, 1.0, 1.0 }), // white
        math.Vec4.init(.{ 1.0, 0.0, 0.0, 1.0 }), // red
        math.Vec4.init(.{ 0.0, 1.0, 0.0, 1.0 }), // green
        math.Vec4.init(.{ 0.0, 0.0, 1.0, 1.0 }), // blue
        math.Vec4.init(.{ 1.0, 1.0, 0.0, 1.0 }), // yellow
        math.Vec4.init(.{ 1.0, 0.0, 1.0, 1.0 }), // magenta
        math.Vec4.init(.{ 0.0, 1.0, 1.0, 1.0 }), // cyan
    };
    var pickedColor: usize = 0;
    var clicked = false;

    var draw: bool = false;
    while (!window.shouldClose()) {
        clicked = false;
        for (window.pollEvents()) |event| {
            switch (event) {
                w.Event.Touch, w.Event.MouseDown, w.Event.MouseUp, w.Event.TouchMove, w.Event.MouseMove => |pos| {
                    x = pos.x();
                    y = pos.y();
                    const tag = std.meta.activeTag(event);
                    switch (tag) {
                        w.Event.MouseDown, w.Event.Touch => {
                            draw = true;
                            clicked = true;
                            std.debug.print("Clicked\n", .{});
                        },
                        w.Event.MouseUp => {
                            draw = false;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
        const cmd = try context.beginDraw();
        try context.acquireSwapchain();
        if (draw) {
            try context.beginPass(
                .{
                    .cmd = cmd,
                    .renderPass = drawingPipeline.renderPass,
                    .clearValues = null,
                    .extent = .{
                        .width = window.width,
                        .height = window.height,
                    },
                    .framebuffer = drawingBuffer,
                },
            );
            try drawingPipeline.draw(cmd, .{
                .center = math.Vec2.init(.{ x, y }),
                .fill = math.Vec4.init(colors[pickedColor].data),
                .radius = 50,
                .resolution = math.Vec2.init(.{ 1920, 1280 }),
            });
            context.endPass();
        }

        {
            // Start swapchain pass
            try context.beginSwapchainPass(.{ .cmd = cmd });
            defer context.endSwapchainPass();
            uiContext.cmd = cmd;
            defer uiContext.cmd = null;

            // Draw canvas
            canvasPipeline.draw(cmd, canvasDescriptor);

            // Draw test rect
            ui.drawRect(.{ .h = 50, .w = 200, .x = 0, .y = 0 }, .{ 1, 0, 0, 1 }, 5, .{ 0, 1, 0, 1 }, 25);

            // Draw color picker ui
            pickedColor = ColorPicker.drawColorPicker(
                &ui,
                .{
                    .clicked = clicked,
                    .pos = .init(.{ @intFromFloat(x), @intFromFloat(y) }),
                },
                .{
                    .pos = .init(.{ -960, 100 }),
                    .picked = pickedColor,
                    .colors = &colors,
                    .size = .init(.{ 1000, 50 }),
                },
            );

            // End swapchain and ui pass
            uiContext.cmd = null;
            context.endSwapchainPass();
        }

        try context.endDraw();
        try context.presentSwpachain();
    }
}
