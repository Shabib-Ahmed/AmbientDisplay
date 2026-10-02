// Lives in SamplePackages/sample-scene-package/Theme/Shaders/ - NOT compiled
// into the app. This is the app-authored *default* version of this effect,
// but mechanically it is just a package shader like any third-party one
// would be: resolved and runtime-compiled by AmbientShaderLibraryCache
// against this theme's themeDirectoryURL. Reference this manifest.json:
// SamplePackages/sample-scene-package/manifest.json
//
// AmbientShaderUniforms, VertexOut, and the AmbientShaderTexture*Index /
// AmbientShaderUniformBufferIndex constants are NOT declared in this
// file - AmbientShaderLibraryCache prepends a shared prelude with all of
// them (plus ambient_hsv2rgb) before compiling. See that file's
// kPackageShaderPrelude if you need the exact declarations.

#include <metal_stdlib>
using namespace metal;

// Port target: old AmbientEffectPrimitiveTypeGradientWash. The old
// primitive's exact parameter set (colors, direction, speed) lived in
// AmbientEffectRecipeLoader.m, which was deleted along with the rest of
// the primitive pipeline and was never re-uploaded here, so its values
// aren't recoverable - this defines a fresh, equivalent parameter set
// rather than guessing at the old one's exact numbers:
//
// params.x -> hueA (0...1), first gradient color
// params.y -> hueB (0...1), second gradient color
// params.z -> angle, radians, direction the gradient axis runs along
// params.w -> speed, drift rate of the wash along that axis over time
//
// Inputs: none - pure function of time + params.
//
// Semi-transparent by design (kWashAlpha below) so the background video
// stays visible underneath rather than being fully replaced - all four
// params slots are already spoken for (hueA/hueB/angle/speed), so alpha
// is a hand-tunable constant here rather than a manifest param; bump it
// toward 1.0 for a more opaque wash, toward 0.0 for more video showing
// through.
static constant float kWashAlpha = 0.5;

fragment float4 fragment_gradientwash(VertexOut in [[stage_in]],
                                       constant AmbientShaderUniforms &uniforms [[buffer(AmbientShaderUniformBufferIndex)]]) {
    float hueA = fract(uniforms.params.x);
    float hueB = fract(uniforms.params.y);
    float angle = uniforms.params.z;
    float speed = uniforms.params.w;

    float2 dir = float2(cos(angle), sin(angle));
    float coord = dot(in.uv - 0.5, dir);

    // A smooth (sin-based, so no hard wrap seam) oscillation between the
    // two hues along the gradient axis, slowly drifting over time.
    float wave = sin((coord + uniforms.time * speed) * 6.2831853) * 0.5 + 0.5;
    float hue = mix(hueA, hueB, wave);

    float3 color = ambient_hsv2rgb(float3(hue, 0.5, 0.55));
    return float4(color, kWashAlpha);
}
