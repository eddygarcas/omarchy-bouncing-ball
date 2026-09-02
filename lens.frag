#version 440

// Gravitational-lensing displacement for the "Black Hole" style's halo.
// Consumed as a ShaderEffect fragmentShader against a ShaderEffectSource
// cropped to a small square of the real desktop wallpaper centered on the
// ball (see Overlay.qml) -- this shader never sees the whole desktop, only
// that patch, so `qt_TexCoord0` is local 0..1 space within it.
//
// `horizon` is the ball's own radius as a fraction of the patch's half-
// width (e.g. 0.25 when the patch is 4x the ball's diameter) -- distortion
// strength is clamped to a soft inverse-square falloff starting there and
// is exactly zero by the patch's outer edge (r == 0.5), so the untouched
// wallpaper just outside the patch lines up seamlessly with this shader's
// own (undistorted-at-the-boundary) output. A second, independent alpha
// falloff over the same span gives the whole patch a soft circular edge
// instead of a visible hard-edged square.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float strength;
    float swirl;
    float horizon;
} ubuf;

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 center = vec2(0.5, 0.5);
    vec2 d = qt_TexCoord0 - center;
    float r = length(d);
    float rClamped = max(r, ubuf.horizon);

    // 1 right at the horizon, fading to 0 by the patch's outer edge.
    float edge = smoothstep(0.5, ubuf.horizon, r);
    float pull = ubuf.strength * edge / (rClamped * rClamped);
    pull = min(pull, 0.18);

    vec2 radial = d / max(r, 0.0001);
    vec2 tangent = vec2(-radial.y, radial.x);
    vec2 offset = radial * pull + tangent * pull * ubuf.swirl;

    vec2 sampleUV = clamp(qt_TexCoord0 - offset, vec2(0.0), vec2(1.0));
    vec4 col = texture(source, sampleUV);

    float alphaFalloff = smoothstep(0.5, 0.36, r);
    fragColor = col * alphaFalloff * ubuf.qt_Opacity;
}
