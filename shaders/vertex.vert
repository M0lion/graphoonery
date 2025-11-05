#version 450

layout(binding = 0) uniform UniformBufferObject {
		mat4 view;
    mat4 transform;
} ubo;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec4 inColor;

layout(location = 0) out vec4 fragColor;

void main() {
    gl_Position = ubo.transform * ubo.view * vec4(inPosition, 1.0);
    fragColor = inColor;
}
