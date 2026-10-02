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

// Port target: old AmbientEffectPrimitiveTypeRadialPulse. Same situation
// as GradientWash - the old primitive's exact parameters lived in the
// deleted, never-re-uploaded AmbientEffectRecipeLoader.m, so this is a
// fresh equivalent parameter set rather than a guess at the old numbers:
//
// params.x -> speed, pulses per second (a full expand-and-reset cycle)
// params.y -> ringWidth, in normalized uv units
// params.z -> hue (0...1)
// params.w -> maxRadius, in normalized uv units, capped by the aspect
//   correction below so the ring stays circular on non-square screens
//
// Inputs: left as none for now, matching the sample manifest - not
// wired to "audioLevels" even though transient-triggered pulses would
// be a natural fit, per that decision being explicitly left open rather
// than assumed.
fragment float4 fragment_radialpulse(VertexOut in [[stage_in]],
                                      constant AmbientShaderUniforms &uniforms [[buffer(AmbientShaderUniformBufferIndex)]]) {
    float speed = max(uniforms.params.x, 0.0);
    float ringWidth = max(uniforms.params.y, 0.01);
    float hue = fract(uniforms.params.z);
    float maxRadius = max(uniforms.params.w, 0.01);

    float aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1.0);
    float2 centered = (in.uv - 0.5) * float2(aspect, 1.0);
    float dist = length(centered);

    float phase = fract(uniforms.time * speed);
    float ringRadius = phase * maxRadius;

    float ringDist = abs(dist - ringRadius) - ringWidth * 0.5;
    float aa = max(fwidth(ringDist), 0.0008);
    float alpha = 1.0 - smoothstep(0.0, aa, ringDist);

    // Fade out as the ring approaches maxRadius so it dissolves rather
    // than vanishing with a hard cut when phase wraps back to 0.
    alpha *= 1.0 - smoothstep(maxRadius * 0.7, maxRadius, ringRadius);

    float3 color = ambient_hsv2rgb(float3(hue, 0.6, 1.0));
    return float4(color, alpha);
}
