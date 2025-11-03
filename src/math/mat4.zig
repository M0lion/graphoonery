const std = @import("std");
const math = std.math;

pub const Mat4 = struct {
    m: [16]f32, // Column-major order

    pub fn identity() Mat4 {
        return Mat4{
            .m = [_]f32{
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            },
        };
    }

    pub fn createOrtho2D(window_width: f32, window_height: f32, world_units_visible: f32) Mat4 {
        const aspect = window_width / window_height;
        var half_height: f32 = undefined;
        var half_width: f32 = undefined;

        if (window_height < window_width) {
            half_height = world_units_visible / 2.0;
            half_width = half_height * aspect;
        } else {
            half_width = world_units_visible / 2.0;
            half_height = half_width / aspect;
        }

        const left = -half_width;
        const right = half_width;
        const bottom = -half_height;
        const top = half_height;
        const near_z: f32 = -1.0;
        const far_z: f32 = 1.0;

        return Mat4{
            .m = [_]f32{
                // Column 0
                2.0 / (right - left),
                0.0,
                0.0,
                0.0,
                // Column 1
                0.0,
                2.0 / (top - bottom),
                0.0,
                0.0,
                // Column 2
                0.0,
                0.0,
                -2.0 / (far_z - near_z),
                0.0,
                // Column 3 (translation)
                -(right + left) / (right - left),
                -(top + bottom) / (top - bottom),
                -(far_z + near_z) / (far_z - near_z),
                1.0,
            },
        };
    }
};
