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

// Port target: old AmbientVisualizerEffectRenderer's
// -waveformPathForLevels:count:bounds: (the quad-curve ribbon version).
// Declares "inputs": ["audioLevels"] in the manifest.
//
// params.x -> minHalfHeight: the ribbon's half-height at silence, in uv
//   units, so it never fully disappears (old default equivalent: a
//   thin resting line).
// params.y -> hue (0...1) of the ribbon.
//
// Uses linear texture filtering when sampling audioLevels, which gives
// smoothing between adjacent bins close to the old bezier/quad-curve
// smoothing essentially for free - no explicit catmull-rom pass needed
// for a visual this small.
fragment float4 fragment_waveform(VertexOut in [[stage_in]],
                                   constant AmbientShaderUniforms &uniforms [[buffer(AmbientShaderUniformBufferIndex)]],
                                   texture2d<float> audioLevels [[texture(AmbientShaderTextureAudioLevelsIndex)]]) {
    constexpr sampler linearSampler(address::clamp_to_edge, filter::linear);

    float minHalfHeight = max(uniforms.params.x, 0.003);
    float hue = fract(uniforms.params.y);

    float level = audioLevels.sample(linearSampler, float2(in.uv.x, 0.5)).r;
    level = clamp(level * uniforms.sensitivity, 0.0, 1.0);

    float halfHeight = minHalfHeight + level * 0.42;
    float dist = abs(in.uv.y - 0.5) - halfHeight;

    float aa = max(fwidth(dist), 0.0008);
    float alpha = 1.0 - smoothstep(0.0, aa, dist);

    float3 color = ambient_hsv2rgb(float3(hue, 0.55, 1.0));
    return float4(color, alpha);
}
