# TODO — composite canvas onto swapchain

Goal: get `drawingImage` (the accumulating stroke canvas) onto the swapchain each
frame, under the UI.

Approach: sample the canvas as a texture with a fullscreen quad in the existing
swapchain pass. Chosen over `vkCmdBlitImage` because `drawingImage` already has
`SAMPLED_BIT` and `canvasRenderPass` already flips it to
`SHADER_READ_ONLY_OPTIMAL` on end — see [Why not a blit](#why-not-a-blit).

---

## 1. Sampler

None exists anywhere in `vulkan/src` yet.

- [ ] Add `createSampler` / `destroySampler` (new `vulkan/src/sampler.zig`, or into
      `images.zig`), export from `vulkan/src/lib.zig`

```zig
const samplerInfo = c.VkSamplerCreateInfo{
    .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
    .magFilter = c.VK_FILTER_LINEAR,
    .minFilter = c.VK_FILTER_LINEAR,
    .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_NEAREST,
    .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
    .mipLodBias = 0.0,
    .anisotropyEnable = c.VK_FALSE,
    .maxAnisotropy = 1.0,
    .compareEnable = c.VK_FALSE,
    .compareOp = c.VK_COMPARE_OP_ALWAYS,
    .minLod = 0.0,
    .maxLod = 0.0,
    .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
    .unnormalizedCoordinates = c.VK_FALSE,
};
```

## 2. `descriptor.zig` — image descriptor support

Currently uniform-buffer-only.

- [ ] `DescriptorType` (`descriptor.zig:5`) — add
      `CombinedImageSampler = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER`
- [ ] `ShaderStage` (`descriptor.zig:8`) — add
      `Fragment = c.VK_SHADER_STAGE_FRAGMENT_BIT`
- [ ] `createDescriptorPool` (`descriptor.zig:54`) — hardcodes one
      `UNIFORM_BUFFER` pool size; add a `COMBINED_IMAGE_SAMPLER` size
- [ ] `updateDescriptorSet` (`descriptor.zig:110`) — writes `pBufferInfo` only;
      needs a `pImageInfo` path

```zig
const imageInfo = c.VkDescriptorImageInfo{
    .sampler = sampler,
    .imageView = drawingImage.imageView,
    .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
};
```

Write the set once at startup — the view never changes, so no per-frame update.

## 3. Shaders

- [ ] `shaders/canvas.vert` — no vertex buffer, 4 verts, triangle strip (same
      shape as `DrawingPipeline`)

```glsl
#version 450
layout(location = 0) out vec2 uv;
void main() {
    uv = vec2(float(gl_VertexIndex & 1), float((gl_VertexIndex >> 1) & 1));
    gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
}
```

- [ ] `shaders/canvas.frag`

```glsl
#version 450
layout(set = 0, binding = 0) uniform sampler2D canvas;
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 outColor;
void main() { outColor = texture(canvas, uv); }
```

- [ ] Confirm the build's shader step picks them up (they land in the `shaders`
      module as `canvas_vert_spv` / `canvas_frag_spv`)

## 4. `CanvasPipeline`

- [ ] New `surface-drawing/src/CanvasPipeline.zig`, modelled on
      `DrawingPipeline.zig` but:
  - `.renderPass = context.swapchainRenderPass`
  - `.descriptorSetLayouts = &.{layout}`
  - `.topology = .TriangleStrip`
  - **no** push constants (so no `pushConstantRanges` needed)

Normalized UV means canvas extent and swapchain extent need not match.

## 5. Synchronization — will bite if skipped

`renderPass.zig` hardcodes `dependencyCount = 0`. The canvas pass's color write
and the swapchain pass's fragment read sit in the same command buffer with
nothing ordering them. The `finalLayout` transition is **not** an execution
dependency.

- [ ] Add a `dependencies` field to `RenderPassConfig` and wire it into
      `createRenderPassInfo` (or drop a `vkCmdPipelineBarrier` between `endPass`
      and `beginSwapchainPass`)

```zig
c.VkSubpassDependency{
    .srcSubpass = 0,
    .dstSubpass = c.VK_SUBPASS_EXTERNAL,
    .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    .dstStageMask = c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
    .srcAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    .dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT,
    .dependencyFlags = 0,
}
```

Symptom if missing: intermittent garbage or a stale frame, plus `SYNC-HAZARD-*`
from the sync-validation layer.

## 6. First-frame canvas layout + contents

`drawingImage` is created `Undefined` (`surface-drawing/src/main.zig:78`), but
`canvasRenderPass` declares `initialLayout = ShaderReadOnlyOptimal` with
`loadOp = Load`. Frame 1 loads undefined contents from the wrong layout. Nothing
ever clears the canvas either.

- [ ] Pick one:
  - one-time `vkCmdPipelineBarrier` `UNDEFINED -> SHADER_READ_ONLY_OPTIMAL`
    before the first pass, or
  - a separate first-frame render pass with `initialLayout = Undefined` +
    `loadOp = Clear` — gets a known blank canvas, probably what you want

## 7. Wire into the frame loop

`surface-drawing/src/main.zig`:

```
beginDraw
acquireSwapchain
beginPass(canvas)        // strokes accumulate, loadOp=Load
  drawingPipeline.draw
endPass
beginSwapchainPass       // clears to blue
  canvasPipeline.draw    // <-- bind set 0, vkCmdDraw(cmd, 4, 1, 0, 0)
  ui.drawRect            // UI on top
endSwapchainPass
endDraw
presentSwpachain
```

- [ ] `vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, canvasPipeline.layout, 0, 1, &set, 0, null)`
      before the quad draw
- [ ] Decide on the blue clear: the quad covers every pixel, so it becomes
      invisible. To let blue show through unpainted canvas, enable alpha blending
      on the canvas pipeline and clear the canvas to transparent instead.

---

## Loose end (unrelated to compositing)

- [ ] `beginPass` (`vulkan/src/vulkanContext.zig:242`) builds `renderArea` from
      `self.width`/`self.height` (swapchain extent) while the canvas framebuffer
      is `window.width x window.height`. Harmless while equal — validation error
      the moment they diverge. `args.extent` is currently used only for the
      scissor.

## Why not a blit

`vkCmdBlitImage` would need:

- `TRANSFER_DST_BIT` added at `vulkan/src/swapchain.zig:202`, checked against
  `surfaceCaps.supportedUsageFlags`
- `TRANSFER_SRC_BIT` on `drawingImage`
- blit issued outside any render pass
- manual barriers on both images
- swapchain pass switched to `loadOp = Load` with
  `initialLayout = COLOR_ATTACHMENT_OPTIMAL`, so its clear doesn't erase the blit

More moving parts than one quad, and no per-draw blending or filtering control.
Only worth it to avoid writing shaders.
