const std = @import("std");
const vulkan = @import("vulkan/build.zig");
const wayland = @import("wayland/build.zig");
const window = @import("window/build.zig");
const testbed = @import("testbed/build.zig");
const surfaceDrawing = @import("surface-drawing/build.zig");
const math = @import("math/build.zig");
const ui = @import("ui/build.zig");

pub fn FooBuilder(
    Dependencies: type,
    createModule: *const fn (
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        dependencies: anytype,
    ) *std.Build.Module,
) type {
    return struct {
        name: []const u8,
        import: ?std.Build.Module.Import = null,

        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,

        fn getImport(
            self: *@This(),
            dependencies: anytype,
        ) std.Build.Module.Import {
            if (self.import) |import| {
                return import;
            } else {
                const deps: Dependencies = undefined;

                for (@typeInfo(Dependencies).@"struct".fields) |field| {
                    @field(deps, field.name) = @field(@TypeOf(dependencies), field.name).getImport(
                        dependencies,
                    );
                }

                const module = createModule(
                    self.b,
                    self.target,
                    self.optimize,
                    deps,
                );
                self.import = std.Build.Module.Import{
                    .name = self.name,
                    .module = module,
                };

                return self.import.?;
            }
        }
    };
}
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Generate shared artifacts once
    const shaders_module = vulkan.compileShaders(b, target, optimize) catch {
        @panic("Failed to compile shaders");
    };
    const shadersImport = std.Build.Module.Import{
        .name = "shaders",
        .module = shaders_module,
    };

    var mathFoo = FooBuilder(math.Dependencies, &math.createModule){
        .name = "math",
        .b = b,
        .target = target,
        .optimize = optimize,
    };
    var uiFoo = FooBuilder(ui.Dependencies, &ui.createModule){
        .name = "ui",
        .b = b,
        .target = target,
        .optimize = optimize,
    };

    const vulkanImport = std.Build.Module.Import{
        .name = "vulkan",
        .module = vulkan.createModule(b, target, optimize),
    };
    const waylandImport = std.Build.Module.Import{
        .name = "wayland",
        .module = wayland.createModule(b, target, optimize),
    };
    const windowImport = std.Build.Module.Import{
        .name = "window",
        .module = window.createModule(b, target, optimize, vulkanImport, mathFoo.getImport({})),
    };

    const testbedModule = testbed.createModule(
        b,
        target,
        optimize,
        vulkanImport,
        windowImport,
    );
    addExe(b, testbedModule, "testbed");

    const surfaceDrawingModule = surfaceDrawing.createModule(
        b,
        target,
        optimize,
        vulkanImport,
        windowImport,
        mathFoo.getImport({}),
        uiFoo.getImport({}),
        shadersImport,
    );
    addExe(b, surfaceDrawingModule, "surfaceDrawing");

    // Executable 1
    const mainModule = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            vulkanImport,
            waylandImport,
        },
    });
    const mainExe = b.addExecutable(.{
        .name = "graphoonery",
        .root_module = mainModule,
    });

    // Linker fix
    mainExe.use_llvm = true;
    mainExe.use_lld = true;

    configureExecutable(b, mainExe, mainModule, target, shaders_module);
    b.installArtifact(mainExe);

    // Executable 2
    const lockscreenModule = b.createModule(.{
        .root_source_file = b.path("src/lockscreen.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            vulkanImport,
            waylandImport,
        },
    });
    const lockscreenExe = b.addExecutable(.{
        .name = "lockfoonery",
        .root_module = lockscreenModule,
    });

    // Linker fix
    lockscreenExe.use_llvm = true;
    lockscreenExe.use_lld = true;

    lockscreenExe.linkSystemLibrary("pam");
    configureExecutable(b, lockscreenExe, lockscreenModule, target, shaders_module);
    b.installArtifact(lockscreenExe);

    // Run step
    const run_cmd = b.addRunArtifact(mainExe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Lock step
    const lockCmd = b.addRunArtifact(lockscreenExe);
    lockCmd.step.dependOn(b.getInstallStep());
    const lockStep = b.step("lock", "Run the lockscreen");
    lockStep.dependOn(&lockCmd.step);
}

fn addExe(
    b: *std.Build,
    module: *std.Build.Module,
    name: []const u8,
) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = module,
    });
    exe.use_llvm = true;
    // LLD can't link mach-o; only force it where it's the intended workaround.
    if (module.resolved_target.?.result.os.tag != .macos) {
        exe.use_lld = true;
    }
    const install = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install.step);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&install.step);
    const run_step = b.step(name, b.fmt("Run {s}", .{name}));
    run_step.dependOn(&run_cmd.step);
}

fn configureExecutable(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    shaders_module: *std.Build.Module,
) void {
    // Add shaders module
    module.addImport("shaders", shaders_module);

    // Platform-specific windowing setup. Vulkan/Metal linking now lives in
    // the vulkan module; what remains here is the custom Cocoa window used by
    // the graphoonery/lockfoonery executables.
    if (target.result.os.tag == .macos) {
        exe.addCSourceFile(.{
            .file = b.path("src/macos_window.m"),
        });
        exe.linkFramework("Cocoa");
    } else {}

    exe.linkLibC();
}
