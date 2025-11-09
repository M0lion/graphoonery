const std = @import("std");
const ColoredVertexPipeline = @import("coloredVertexPipeline.zig").ColoredVertexPipeline;

pub fn getDodecahedron(
    allocator: std.mem.Allocator,
    coloredVertexPipeline: *ColoredVertexPipeline,
) !ColoredVertexPipeline.Mesh {
    const vertices = try generateDodecahedron(allocator);
    const mesh = try ColoredVertexPipeline.Mesh.init(coloredVertexPipeline, vertices);
    return mesh;
}

fn generateDodecahedron(allocator: std.mem.Allocator) ![]ColoredVertexPipeline.Vertex {
    const phi = (1.0 + @sqrt(5.0)) / 2.0; // Golden ratio
    const invPhi = 1.0 / phi;

    // Define the 20 vertices of a dodecahedron
    const positions = [20][3]f32{
        // Cube vertices (±1, ±1, ±1)
        .{ 1, 1, 1 },
        .{ 1, 1, -1 },
        .{ 1, -1, 1 },
        .{ 1, -1, -1 },
        .{ -1, 1, 1 },
        .{ -1, 1, -1 },
        .{ -1, -1, 1 },
        .{ -1, -1, -1 },
        // Rectangle vertices (0, ±1/φ, ±φ)
        .{ 0, invPhi, phi },
        .{ 0, invPhi, -phi },
        .{ 0, -invPhi, phi },
        .{ 0, -invPhi, -phi },
        // Rectangle vertices (±1/φ, ±φ, 0)
        .{ invPhi, phi, 0 },
        .{ invPhi, -phi, 0 },
        .{ -invPhi, phi, 0 },
        .{ -invPhi, -phi, 0 },
        // Rectangle vertices (±φ, 0, ±1/φ)
        .{ phi, 0, invPhi },
        .{ phi, 0, -invPhi },
        .{ -phi, 0, invPhi },
        .{ -phi, 0, -invPhi },
    };

    // Define the 12 pentagonal faces (vertex indices in counter-clockwise order)
    const faces = [12][5]u8{
        .{ 0, 8, 10, 2, 16 },
        .{ 0, 16, 17, 1, 12 },
        .{ 0, 12, 14, 4, 8 },
        .{ 1, 17, 3, 11, 9 },
        .{ 1, 9, 5, 14, 12 },
        .{ 2, 10, 6, 15, 13 },
        .{ 2, 13, 3, 17, 16 },
        .{ 3, 13, 15, 7, 11 },
        .{ 4, 14, 5, 19, 18 },
        .{ 4, 18, 6, 10, 8 },
        .{ 5, 9, 11, 7, 19 },
        .{ 6, 18, 19, 7, 15 },
    };

    // 12 different colors for the 12 faces
    const colors = [12][4]f32{
        .{ 1, 0, 0, 1 }, // Red
        .{ 0, 1, 0, 1 }, // Green
        .{ 0, 0, 1, 1 }, // Blue
        .{ 1, 1, 0, 1 }, // Yellow
        .{ 1, 0, 1, 1 }, // Magenta
        .{ 0, 1, 1, 1 }, // Cyan
        .{ 1, 0.5, 0, 1 }, // Orange
        .{ 0.5, 0, 1, 1 }, // Purple
        .{ 0, 1, 0.5, 1 }, // Teal
        .{ 1, 0, 0.5, 1 }, // Pink
        .{ 0.5, 1, 0, 1 }, // Lime
        .{ 1, 1, 1, 1 }, // White
    };

    var vertices = try std.ArrayList(ColoredVertexPipeline.Vertex).initCapacity(allocator, faces.len * 9);

    // Generate triangles for each pentagonal face
    for (faces, 0..) |face, faceIdx| {
        const color = colors[faceIdx];

        // Calculate face normal
        const v0 = positions[face[0]];
        const v1 = positions[face[1]];
        const v2 = positions[face[2]];

        const edge1 = [3]f32{ v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2] };
        const edge2 = [3]f32{ v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2] };

        // Cross product for normal
        var normal = [3]f32{
            edge1[1] * edge2[2] - edge1[2] * edge2[1],
            edge1[2] * edge2[0] - edge1[0] * edge2[2],
            edge1[0] * edge2[1] - edge1[1] * edge2[0],
        };

        // Normalize
        const length = @sqrt(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2]);
        normal[0] /= length;
        normal[1] /= length;
        normal[2] /= length;

        const normal4 = [4]f32{ normal[0], normal[1], normal[2], 0 };

        // Triangulate pentagon using fan triangulation (0-1-2, 0-2-3, 0-3-4)
        // Triangle 1: vertices 0, 1, 2
        try vertices.append(allocator, .{
            .position = positions[face[0]],
            .color = color,
            .normal = normal4,
        });
        try vertices.append(allocator, .{
            .position = positions[face[1]],
            .color = color,
            .normal = normal4,
        });
        try vertices.append(allocator, .{
            .position = positions[face[2]],
            .color = color,
            .normal = normal4,
        });

        // Triangle 2: vertices 0, 2, 3
        try vertices.append(allocator, .{
            .position = positions[face[0]],
            .color = color,
            .normal = normal4,
        });
        try vertices.append(allocator, .{
            .position = positions[face[2]],
            .color = color,
            .normal = normal4,
        });
        try vertices.append(allocator, .{
            .position = positions[face[3]],
            .color = color,
            .normal = normal4,
        });

        // Triangle 3: vertices 0, 3, 4
        try vertices.append(allocator, .{
            .position = positions[face[0]],
            .color = color,
            .normal = normal4,
        });
        try vertices.append(allocator, .{
            .position = positions[face[3]],
            .color = color,
            .normal = normal4,
        });
        try vertices.append(allocator, .{
            .position = positions[face[4]],
            .color = color,
            .normal = normal4,
        });
    }

    return vertices.toOwnedSlice(allocator);
}
