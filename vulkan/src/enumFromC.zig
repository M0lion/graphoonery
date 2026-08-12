const std = @import("std");
const c = @import("vk.zig").c;

pub fn EnumFromC(comptime import: type, comptime prefix: []const u8, comptime Tag: type) type {
    comptime var names: []const [:0]const u8 = &.{};
    comptime var values: []const Tag = &.{};

    @setEvalBranchQuota(1_000_000); // Vulkan has a LOT of decls
    inline for (std.meta.declarations(import)) |decl| {
        if (!std.mem.startsWith(u8, decl.name, prefix)) continue;

        const v = @field(import, decl.name);
        if (@TypeOf(v) != c_int and @TypeOf(v) != c_uint) continue; // skip macros/fns

        // Vulkan aliases names to the same value (e.g. *_KHR promoted to core);
        // enums can't have two fields with the same value, so dedup.
        comptime var seen = false;
        inline for (values) |existing| {
            if (existing == @as(Tag, @intCast(v))) {
                seen = true;
                break;
            }
        }
        if (seen) continue;

        names = names ++ .{decl.name[prefix.len..]};
        values = values ++ &[_]Tag{@intCast(v)};
    }

    comptime var fields: []const std.builtin.Type.EnumField = &.{};
    inline for (names, values) |n, val| {
        //@compileLog(n);
        fields = fields ++ &[_]std.builtin.Type.EnumField{
            .{ .name = n, .value = val }, // .name must be [:0]const u8enuf
        };
    }
    return @Type(.{ .@"enum" = .{
        .tag_type = Tag,
        .fields = fields,
        .decls = &.{},
        .is_exhaustive = false,
    } });
}
