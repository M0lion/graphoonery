const std = @import("std");
const Window = @import("window").Window;
const vulkan = @import("vulkan");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    var window = Window.init(500, 500);
    defer window.deinit();

    var context = try window.getVulkanContext(allocator);

    while (!window.shouldClose()) {
        if (window.input.down(.ESCAPE)) {
            break;
        }
        _ = try context.beginDraw();
        try context.endDraw();
        window.pollEvents();
    }
}
