#version 450

layout(location = 0) in vec4 fragColor;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec3 pos;

layout(location = 0) out vec4 outColor;

void main() {
		float luminance = 1;
		vec3 pointLight = vec3(-1,0,3);
    // Hardcoded light direction (pointing down and to the right)
    vec3 lightDir = pos - pointLight;
		float dist = length(lightDir);
		float flux = luminance/(4*3.14*(dist*dist));
    
    // Simple diffuse lighting
    float diffuse = max(dot(normalize(normal), -normalize(lightDir)), 0.0);
    
    // Add some ambient so faces aren't completely black
    float ambient = 0.0;
    float lighting = ambient + (1.0 - ambient) * diffuse * flux;
    
    outColor = vec4(fragColor.rgb * lighting, fragColor.a);
}
