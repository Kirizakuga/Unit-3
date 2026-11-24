#version 440
// Makes the dark (black) part of the unlock video transparent so the desktop shows through.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec4 c = texture(source, qt_TexCoord0);
    float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
    float a = smoothstep(0.10, 0.30, l) * qt_Opacity;
    fragColor = vec4(c.rgb * a, a);   // premultiplied alpha
}
