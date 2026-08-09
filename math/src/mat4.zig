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

    pub fn multiply(self: *const Mat4, other: *const Mat4) Mat4 {
        var result: Mat4 = undefined;

        // For each column of the result
        inline for (0..4) |col| {
            // For each row of the result
            inline for (0..4) |row| {
                var sum: f32 = 0.0;

                // Dot product of row from self with column from other
                inline for (0..4) |i| {
                    sum += self.m[i * 4 + row] * other.m[col * 4 + i];
                }

                result.m[col * 4 + row] = sum;
            }
        }

        return result;
    }

    pub fn createTranslation(x: f32, y: f32, z: f32) Mat4 {
        return Mat4{
            .m = [_]f32{
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                x,   y,   z,   1.0,
            },
        };
    }

    // Then use:
    const model = Mat4.createTranslation(0, 0, -5);

    pub fn createRotation(yaw: f32, pitch: f32, roll: f32) Mat4 {
        const cosYaw = @cos(yaw);
        const cosPitch = @cos(pitch);
        const cosRoll = @cos(roll);
        const sinYaw = @sin(yaw);
        const sinPitch = @sin(pitch);
        const sinRoll = @sin(roll);

        return Mat4{
            .m = [_]f32{
                // Row 0
                cosYaw * cosPitch,
                cosYaw * sinPitch * sinRoll - sinYaw * cosRoll,
                cosYaw * sinPitch * cosRoll + sinYaw * sinRoll,
                0.0,

                // Row 1
                sinYaw * cosPitch,
                sinYaw * sinPitch * sinRoll + cosYaw * cosRoll,
                sinYaw * sinPitch * cosRoll - cosYaw * sinRoll,
                0.0,

                // Row 2
                -sinPitch,
                cosPitch * sinRoll,
                cosPitch * cosRoll,
                0.0,

                // Row 3
                0.0,
                0.0,
                0.0,
                1.0,
            },
        };
    }

    pub fn createPerspective(fov_degrees: f32, aspect: f32, near_z: f32, far_z: f32) Mat4 {
        const fov_rad = fov_degrees * std.math.pi / 180.0;
        const f = 1.0 / @tan(fov_rad / 2.0);

        // Vulkan depth range [0, 1]
        return Mat4{
            .m = [_]f32{
                // Column 0
                f / aspect,
                0.0,
                0.0,
                0.0,
                // Column 1
                0.0,
                f, // Use -f if you want Y-axis flipped for Vulkan
                0.0,
                0.0,
                // Column 2
                0.0,
                0.0,
                far_z / (near_z - far_z),
                -1.0,
                // Column 3
                0.0,
                0.0,
                (near_z * far_z) / (near_z - far_z),
                0.0,
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
        const near_z: f32 = -100.0;
        const far_z: f32 = 100.0;

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
                -1.0 / (far_z - near_z),
                0.0,
                // Column 3 (translation)
                -(right + left) / (right - left),
                -(top + bottom) / (top - bottom),
                -near_z / (far_z - near_z),
                1.0,
            },
        };
    }
};
