#version 450

layout(location = 0) in vec2 vLocal;
layout(location = 0) out vec4 outColor;

layout(push_constant) uniform PC {
    vec2  uResolution;
    vec2  uCenter;      // rect center, pixels
    vec2  uHalfSize;    // rect half-extents, pixels
    float uRadius;
    float uBorder;
    vec4  uFill;
    vec4  uBorderColor;
} pc;

float sdRoundedBox(vec2 p, vec2 halfSize, float r) {
	vec2 q = abs(p) - halfSize + r;
	return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    float d  = sdRoundedBox(vLocal, pc.uHalfSize, pc.uRadius);
    float aa = fwidth(d);                              // ~1px in distance units

    float shape = clamp(0.5 - d / aa, 0.0, 1.0);              // outer coverage
    float inner = clamp(0.5 - (d + pc.uBorder) / aa, 0.0, 1.0); // inside the border

    vec3  rgb   = mix(pc.uBorderColor.rgb, pc.uFill.rgb, inner);
    float alpha = mix(pc.uBorderColor.a,   pc.uFill.a,   inner);
    outColor    = vec4(rgb, alpha * shape);
}
