const std = @import("std");

/// Generic, Vulkan-friendly vector type.
///
/// The data is stored as a tightly packed array inside an `extern struct`,
/// so the memory layout is guaranteed and matches what Vulkan expects for
/// vertex attributes (e.g. VK_FORMAT_R32G32B32_SFLOAT for Vec(3, f32)).
/// You can memcpy slices of these straight into a vertex buffer.
///
/// Note for uniform buffers: std140 layout aligns vec3 to 16 bytes, so for
/// UBO structs prefer Vec(4, f32) or add explicit padding. For vertex input
/// and std430/scalar layouts, the tight packing here is exactly right.
pub fn Vec(comptime n: comptime_int, comptime T: type) type {
    if (n < 1) @compileError("Vec must have at least 1 component");

    return extern struct {
        const Self = @This();
        const Simd = @Vector(n, T);

        pub const dimensions = n;
        pub const Scalar = T;

        data: [n]T,

        pub const zero = splat(0);
        pub const one = splat(1);

        // ---------- construction ----------

        pub fn init(values: [n]T) Self {
            return .{ .data = values };
        }

        pub fn splat(value: T) Self {
            return .{ .data = @as(Simd, @splat(value)) };
        }

        /// Expose the underlying SIMD vector for custom math.
        pub fn vector(self: Self) Simd {
            return self.data;
        }

        pub fn fromVector(v: Simd) Self {
            return .{ .data = v };
        }

        // ---------- component access ----------

        pub fn x(self: Self) T {
            return self.data[0];
        }

        pub fn y(self: Self) T {
            comptime if (n < 2) @compileError("Vec has no y component");
            return self.data[1];
        }

        pub fn z(self: Self) T {
            comptime if (n < 3) @compileError("Vec has no z component");
            return self.data[2];
        }

        pub fn w(self: Self) T {
            comptime if (n < 4) @compileError("Vec has no w component");
            return self.data[3];
        }

        // ---------- arithmetic ----------

        pub fn add(a: Self, b: Self) Self {
            return fromVector(a.vector() + b.vector());
        }

        pub fn sub(a: Self, b: Self) Self {
            return fromVector(a.vector() - b.vector());
        }

        /// Component-wise multiplication (Hadamard product).
        pub fn mul(a: Self, b: Self) Self {
            return fromVector(a.vector() * b.vector());
        }

        /// Component-wise division.
        pub fn div(a: Self, b: Self) Self {
            return fromVector(a.vector() / b.vector());
        }

        pub fn scale(self: Self, s: T) Self {
            return fromVector(self.vector() * @as(Simd, @splat(s)));
        }

        pub fn neg(self: Self) Self {
            comptime assertSigned();
            return fromVector(-self.vector());
        }

        // ---------- geometry ----------

        pub fn dot(a: Self, b: Self) T {
            return @reduce(.Add, a.vector() * b.vector());
        }

        /// Squared length. Cheap; prefer it for comparisons.
        pub fn lengthSq(self: Self) T {
            return dot(self, self);
        }

        pub fn length(self: Self) T {
            comptime assertFloat("length");
            return @sqrt(self.lengthSq());
        }

        pub fn distance(a: Self, b: Self) T {
            comptime assertFloat("distance");
            return sub(a, b).length();
        }

        /// Returns the zero vector if the input has zero length.
        pub fn normalize(self: Self) Self {
            comptime assertFloat("normalize");
            const len = self.length();
            if (len == 0) return zero;
            return self.scale(1.0 / len);
        }

        /// Cross product. Only defined for 3-component vectors.
        pub fn cross(a: Self, b: Self) Self {
            comptime if (n != 3) @compileError("cross is only defined for Vec(3, T)");
            return init(.{
                a.data[1] * b.data[2] - a.data[2] * b.data[1],
                a.data[2] * b.data[0] - a.data[0] * b.data[2],
                a.data[0] * b.data[1] - a.data[1] * b.data[0],
            });
        }

        /// Linear interpolation: a when t == 0, b when t == 1.
        pub fn lerp(a: Self, b: Self, t: T) Self {
            comptime assertFloat("lerp");
            return add(a, sub(b, a).scale(t));
        }

        // ---------- comparison ----------

        pub fn eql(a: Self, b: Self) bool {
            return @reduce(.And, a.vector() == b.vector());
        }

        pub fn approxEql(a: Self, b: Self, tolerance: T) bool {
            comptime assertFloat("approxEql");
            const diff = @abs(a.vector() - b.vector());
            return @reduce(.And, diff <= @as(Simd, @splat(tolerance)));
        }

        // ---------- helpers ----------

        fn assertFloat(comptime op: []const u8) void {
            if (@typeInfo(T) != .float) {
                @compileError(op ++ " requires a floating-point component type");
            }
        }

        fn assertSigned() void {
            switch (@typeInfo(T)) {
                .float => {},
                .int => |info| if (info.signedness != .signed) {
                    @compileError("neg requires a signed component type");
                },
                else => @compileError("neg requires a numeric component type"),
            }
        }
    };
}

// Common aliases for graphics work.
pub const Vec2 = Vec(2, f32);
pub const Vec3 = Vec(3, f32);
pub const Vec4 = Vec(4, f32);

pub const IVec2 = Vec(2, i32);
pub const IVec3 = Vec(3, i32);

// ---------- tests ----------

test "layout is tightly packed for Vulkan" {
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(Vec3));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Vec4));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Vec3, "data"));
}

test "basic math" {
    const a = Vec3.init(.{ 1, 2, 3 });
    const b = Vec3.init(.{ 4, 5, 6 });

    try std.testing.expect(a.add(b).eql(Vec3.init(.{ 5, 7, 9 })));
    try std.testing.expectEqual(@as(f32, 32), a.dot(b));
    try std.testing.expect(a.cross(b).eql(Vec3.init(.{ -3, 6, -3 })));
    try std.testing.expectApproxEqAbs(@as(f32, 1), a.normalize().length(), 1e-6);
}

test "splat and lerp" {
    const a = Vec2.splat(0);
    const b = Vec2.splat(10);
    try std.testing.expect(a.lerp(b, 0.5).eql(Vec2.splat(5)));
}
