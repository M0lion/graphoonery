const ColoredVertexPipeline = @import("coloredVertexPipeline.zig").ColoredVertexPipeline;

pub fn getCube(coloredVertexPipeline: *ColoredVertexPipeline) !ColoredVertexPipeline.Mesh {
    return try ColoredVertexPipeline.Mesh.init(coloredVertexPipeline, &vertices);
}

const frontFaceColor = [4]f32{ 0, 1, 0, 1 };
const backFaceColor = [4]f32{ 0, 0, 1, 1 };
const rightFaceColor = [4]f32{ 1, 0.4, 0, 1 };
const leftFaceColor = [4]f32{ 1, 0, 0, 1 };
const topFaceColor = [4]f32{ 1, 1, 0, 1 };
const bottomFaceColor = [4]f32{ 1, 1, 1, 1 };

const frontFaceNormal = [4]f32{ 0, 0, 1, 0 };
const backFaceNormal = [4]f32{ 0, 0, -1, 0 };
const rightFaceNormal = [4]f32{ 1, 0, 0, 0 };
const leftFaceNormal = [4]f32{ -1, 0, 0, 0 };
const topFaceNormal = [4]f32{ 0, 1, 0, 0 };
const bottomFaceNormal = [4]f32{ 0, -1, 0, 0 };

var vertices = [_]ColoredVertexPipeline.Vertex{
    // Front face (z = 1) - Red
    .{
        .position = .{ -1, -1, 1 },
        .color = frontFaceColor,
        .normal = frontFaceNormal,
    },
    .{
        .position = .{ 1, -1, 1 },
        .color = frontFaceColor,
        .normal = frontFaceNormal,
    },
    .{
        .position = .{ 1, 1, 1 },
        .color = frontFaceColor,
        .normal = frontFaceNormal,
    },
    .{
        .position = .{ -1, -1, 1 },
        .color = frontFaceColor,
        .normal = frontFaceNormal,
    },
    .{
        .position = .{ 1, 1, 1 },
        .color = frontFaceColor,
        .normal = frontFaceNormal,
    },
    .{
        .position = .{ -1, 1, 1 },
        .color = frontFaceColor,
        .normal = frontFaceNormal,
    },

    // Back face (z = -1) - Green
    .{
        .position = .{ 1, -1, -1 },
        .color = backFaceColor,
        .normal = backFaceNormal,
    },
    .{
        .position = .{ -1, -1, -1 },
        .color = backFaceColor,
        .normal = backFaceNormal,
    },
    .{
        .position = .{ -1, 1, -1 },
        .color = backFaceColor,
        .normal = backFaceNormal,
    },
    .{
        .position = .{ 1, -1, -1 },
        .color = backFaceColor,
        .normal = backFaceNormal,
    },
    .{
        .position = .{ -1, 1, -1 },
        .color = backFaceColor,
        .normal = backFaceNormal,
    },
    .{
        .position = .{ 1, 1, -1 },
        .color = backFaceColor,
        .normal = backFaceNormal,
    },

    // Right face (x = 1) - Blue
    .{
        .position = .{ 1, -1, 1 },
        .color = rightFaceColor,
        .normal = rightFaceNormal,
    },
    .{
        .position = .{ 1, -1, -1 },
        .color = rightFaceColor,
        .normal = rightFaceNormal,
    },
    .{
        .position = .{ 1, 1, -1 },
        .color = rightFaceColor,
        .normal = rightFaceNormal,
    },
    .{
        .position = .{ 1, -1, 1 },
        .color = rightFaceColor,
        .normal = rightFaceNormal,
    },
    .{
        .position = .{ 1, 1, -1 },
        .color = rightFaceColor,
        .normal = rightFaceNormal,
    },
    .{
        .position = .{ 1, 1, 1 },
        .color = rightFaceColor,
        .normal = rightFaceNormal,
    },

    // Left face (x = -1) - Yellow
    .{
        .position = .{ -1, -1, -1 },
        .color = leftFaceColor,
        .normal = leftFaceNormal,
    },
    .{
        .position = .{ -1, -1, 1 },
        .color = leftFaceColor,
        .normal = leftFaceNormal,
    },
    .{
        .position = .{ -1, 1, 1 },
        .color = leftFaceColor,
        .normal = leftFaceNormal,
    },
    .{
        .position = .{ -1, -1, -1 },
        .color = leftFaceColor,
        .normal = leftFaceNormal,
    },
    .{
        .position = .{ -1, 1, 1 },
        .color = leftFaceColor,
        .normal = leftFaceNormal,
    },
    .{
        .position = .{ -1, 1, -1 },
        .color = leftFaceColor,
        .normal = leftFaceNormal,
    },

    // Top face (y = 1) - Cyan
    .{
        .position = .{ -1, 1, 1 },
        .color = topFaceColor,
        .normal = topFaceNormal,
    },
    .{
        .position = .{ 1, 1, 1 },
        .color = topFaceColor,
        .normal = topFaceNormal,
    },
    .{
        .position = .{ 1, 1, -1 },
        .color = topFaceColor,
        .normal = topFaceNormal,
    },
    .{
        .position = .{ -1, 1, 1 },
        .color = topFaceColor,
        .normal = topFaceNormal,
    },
    .{
        .position = .{ 1, 1, -1 },
        .color = topFaceColor,
        .normal = topFaceNormal,
    },
    .{
        .position = .{ -1, 1, -1 },
        .color = topFaceColor,
        .normal = topFaceNormal,
    },

    // Bottom face (y = -1) - Magenta
    .{
        .position = .{ -1, -1, -1 },
        .color = bottomFaceColor,
        .normal = bottomFaceNormal,
    },
    .{
        .position = .{ 1, -1, -1 },
        .color = bottomFaceColor,
        .normal = bottomFaceNormal,
    },
    .{
        .position = .{ 1, -1, 1 },
        .color = bottomFaceColor,
        .normal = bottomFaceNormal,
    },
    .{
        .position = .{ -1, -1, -1 },
        .color = bottomFaceColor,
        .normal = bottomFaceNormal,
    },
    .{
        .position = .{ 1, -1, 1 },
        .color = bottomFaceColor,
        .normal = bottomFaceNormal,
    },
    .{
        .position = .{ -1, -1, 1 },
        .color = bottomFaceColor,
        .normal = bottomFaceNormal,
    },
};
