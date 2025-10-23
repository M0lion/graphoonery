pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vulkan_metal.h"); // For VK_EXT_metal_surface
    @cInclude("vulkan/vulkan_wayland.h");
});

// Re-export common types for convenience
pub const Instance = c.VkInstance;
pub const PhysicalDevice = c.VkPhysicalDevice;
pub const Device = c.VkDevice;
pub const SurfaceKHR = c.VkSurfaceKHR;
pub const SwapchainKHR = c.VkSwapchainKHR;
pub const Result = c.VkResult;

pub const SUCCESS = c.VK_SUCCESS;
pub const API_VERSION_1_0 = c.VK_API_VERSION_1_0;

// Helper to check results
pub fn checkResult(result: Result) !void {
    if (result != SUCCESS) {
        return error.VulkanError;
    }
}
