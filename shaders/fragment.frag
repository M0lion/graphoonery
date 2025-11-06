#version 450

layout(location = 0) in vec4 fragColor;
layout(location = 1) in vec3 normal;

layout(location = 0) out vec4 outColor;

void main() {
    // Hardcoded light direction (pointing down and to the right)
    vec3 lightDir = normalize(vec3(0.5, -0.7, -0.5));
    
    // Simple diffuse lighting
    float diffuse = max(dot(normalize(normal), lightDir), 0.0);
    
    // Add some ambient so faces aren't completely black
    float ambient = 0.3;
    float lighting = ambient + (1.0 - ambient) * diffuse;
    
    outColor = vec4(fragColor.rgb * lighting, fragColor.a);
}
