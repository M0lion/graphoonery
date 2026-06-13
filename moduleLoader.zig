const std = @import("std");

const modules = struct {
    const vulkan = @import("vulkan/build.zig");
    const wayland = @import("wayland/build.zig");
    const window = @import("window/build.zig");
    const ui = @import("ui/build.zig");
    const testbed = @import("testbed/build.zig");
    const math = @import("math/build.zig");
    const shaders = struct {
        pub fn getModule(m: *Modules) *std.Build.Module {
            return m.shaders;
        }
    };
};

pub const Modules = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,

    cache: std.StringHashMap(std.Build.Module.Import),

    shaders: *std.Build.Module,

    pub fn init(
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        shaders: *std.Build.Module,
    ) Modules {
        const cache = std.StringHashMap(std.Build.Module.Import).init(b.allocator);
        return Modules{
            .cache = cache,
            .b = b,
            .target = target,
            .optimize = optimize,
            .shaders = shaders,
        };
    }

    pub fn getImport(self: *Modules, comptime name: []const u8) std.Build.Module.Import {
        if (self.cache.getEntry(name)) |entry| {
            return entry.value_ptr.*;
        }

        const module = @field(modules, name).getModule(self);
        const import = std.Build.Module.Import{
            .name = name,
            .module = module,
        };

        self.cache.put(name, import) catch @panic("failed to put in module cache");
        return import;
    }

    pub fn deinit(self: *Modules) void {
        self.modules.deinit();
    }
};
