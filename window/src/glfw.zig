pub const c = @cImport({
    @cDefine("GLFW_EXPOSE_NATIVE_WAYLAND", "true");
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
});
