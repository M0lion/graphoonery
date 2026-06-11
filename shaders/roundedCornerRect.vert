#version 450

layout(push_constant) uniform PC {
    vec2  uResolution;
    vec2  uCenter;      // rect center, pixels
    vec2  uHalfSize;    // rect half-extents, pixels
    float uRadius;
    float uBorder;
    vec4  uFill;
    vec4  uBorderColor;
} pc;

layout(location = 0) out vec2 vLocal;

void main() {
	vec2 c[4] = vec2[](vec2(-1,-1), vec2(1,-1), vec2(-1,1), vec2(1,1));
	vec2 local = c[gl_VertexIndex] * pc.uHalfSize;
	vec2 screen = pc.uCenter + local;
	vec2 ndc    = (screen / pc.uResolution) * 2.0 - 1.0;
	gl_Position = vec4(ndc, 0.0, 1.0);
	vLocal      = local;
}
