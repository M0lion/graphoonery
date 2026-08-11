#version 450

layout(location = 0) in vec2 vLocal;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform PC {
    vec2  uResolution;
    vec2  uCenter;      // rect center, pixels
    vec4  uFill;
		float uRadius;
} pc;

float sdCircle(vec2 p, float r) {
	float d = r - length(p);
	return d;
}

void main() {
    outColor    = vec4(pc.uFill.rgb, (sdCircle(vLocal, pc.uRadius)));
}
