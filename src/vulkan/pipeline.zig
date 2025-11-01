const std = @import("std");
const vk = @import("vk.zig");
const c = vk.c;

pub const PipelineConfig = struct {
    logicalDevice: c.VkDevice,
    vertShaderModule: c.VkShaderModule,
    fragShaderModule: c.VkShaderModule,
    width: u32,
    height: u32,
    renderPass: c.VkRenderPass,
};

pub const PipelineResult = struct {
    pipeline: c.VkPipeline,
    layout: c.VkPipelineLayout,
};

pub fn createGraphicsPipeline(config: PipelineConfig) !PipelineResult {
    const vertShaderStageInfo = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = config.vertShaderModule,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const fragShaderStageInfo = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = config.fragShaderModule,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const shaderStages = [_]c.VkPipelineShaderStageCreateInfo{ vertShaderStageInfo, fragShaderStageInfo };

    var vertexInputInfo = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
    };

    var inputAssembly = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    var viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(config.width),
        .height = @floatFromInt(config.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    var scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = c.VkExtent2D{
            .width = config.width,
            .height = config.height,
        },
    };

    var viewportState = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };

    var rasterizer = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
        .lineWidth = 1.0,
    };

    var multisampling = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = c.VK_FALSE,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = c.VK_FALSE,
        .alphaToOneEnable = c.VK_FALSE,
    };

    var colorBlendAttachment = c.VkPipelineColorBlendAttachmentState{
        .blendEnable = c.VK_FALSE,
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT |
            c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
        .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .colorBlendOp = c.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
    };

    var colorBlending = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &colorBlendAttachment,
        .blendConstants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    var pipelineLayoutInfo = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };

    var pipelineLayout: c.VkPipelineLayout = undefined;
    try vk.checkResult(c.vkCreatePipelineLayout(
        config.logicalDevice,
        &pipelineLayoutInfo,
        null,
        &pipelineLayout,
    ));

    var pipelineInfo = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stageCount = 2,
        .pStages = &shaderStages,
        .pVertexInputState = &vertexInputInfo,
        .pInputAssemblyState = &inputAssembly,
        .pViewportState = &viewportState,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = null,
        .pColorBlendState = &colorBlending,
        .pDynamicState = null,
        .layout = pipelineLayout,
        .renderPass = config.renderPass,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
        .pTessellationState = null,
    };

    var graphicsPipeline: c.VkPipeline = undefined;
    try vk.checkResult(c.vkCreateGraphicsPipelines(
        config.logicalDevice,
        null,
        1,
        &pipelineInfo,
        null,
        &graphicsPipeline,
    ));

    return PipelineResult{
        .pipeline = graphicsPipeline,
        .layout = pipelineLayout,
    };
}
