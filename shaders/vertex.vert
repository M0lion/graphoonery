#version 450

layout(binding = 0) uniform UniformBufferObject {
		mat4 view;
    mat4 transform;
} ubo;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec4 inColor;
layout(location = 2) in vec3 inNormal;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec3 normal;
layout(location = 2) out vec3 pos;
layout(location = 3) out vec3 uv;

void main() {
	mat4 transform = ubo.transform * ubo.view;
    gl_Position = transform * vec4(inPosition, 1.0);
    fragColor = inColor;
		normal = (transform * vec4(inNormal, 0.0)).xyz;
		pos = gl_Position.xyz;
		uv = inPosition;
}
