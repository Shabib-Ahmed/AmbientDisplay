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
// -barsPathForLevels:count:bounds: (CAShapeLayer/UIBezierPath version).
// Declares "inputs": ["audioLevels"] in the manifest.
//
// params.x -> gapRatio: fraction (0...0.9) of each bar's slot given to
//   the gap between bars, rather than the bar itself.
// params.y -> cornerRadius, as a fraction (0...1) of the bar's own half
//   width (0 = sharp rectangle, 1 = fully rounded pill) - chosen as a
//   resolution-independent unit rather than the old point-size default,
//   since a fragment shader has no natural "point" without assuming a
//   fixed screen density.
// params.z -> idleFloor (0...1): a minimum bar height shown even at
//   silence, so the layer reads as "idle" rather than indistinguishable
//   from a build/binding failure. 0 = old behavior (fully invisible at
//   silence).
//
// audioLevels' texture width IS the bar count (AmbientAudioLevelsTextureProvider's
// canonicalWidth) - read via get_width() rather than a separate param,
// so a package never needs to keep a bar count in sync with the
// provider's fixed width by hand.
fragment float4 fragment_bars(VertexOut in [[stage_in]],
                               constant AmbientShaderUniforms &uniforms [[buffer(AmbientShaderUniformBufferIndex)]],
                               texture2d<float> audioLevels [[texture(AmbientShaderTextureAudioLevelsIndex)]]) {
    uint barCount = audioLevels.get_width();
    if (barCount == 0) {
        return float4(0.0);
    }

    constexpr sampler nearestSampler(address::clamp_to_edge, filter::nearest);

    float gapRatio = clamp(uniforms.params.x, 0.0, 0.9);
    float cornerFraction = clamp(uniforms.params.y, 0.0, 1.0);
    float idleFloor = clamp(uniforms.params.z, 0.0, 1.0);

    float2 uv = in.uv;
    float slotWidth = 1.0 / float(barCount);
    uint barIndex = min(uint(uv.x / slotWidth), barCount - 1);
    float slotCenterX = (float(barIndex) + 0.5) * slotWidth;

    // Nearest sampling - each bar should reflect exactly one bin, not a
    // blend with its neighbor.
    float level = audioLevels.sample(nearestSampler, float2((float(barIndex) + 0.5) / float(barCount), 0.5)).r;
    level = clamp(level * uniforms.sensitivity, 0.0, 1.0);
    level = max(level, idleFloor);
    if (level <= 0.0001) {
        return float4(0.0);
    }

    float barHalfWidth = slotWidth * (1.0 - gapRatio) * 0.5;
    if (barHalfWidth <= 0.0) {
        return float4(0.0);
    }

    // uv.y = 0 is the BOTTOM of the screen, uv.y = 1 is the TOP (Metal's
    // NDC y-axis points up, and that carries through this file's
    // fullscreen-triangle uv mapping) - bars are anchored at the bottom
    // and grow upward as level increases, like a conventional equalizer.
    float barBottom = 0.0;
    float barTop = level;
    float barCenterY = (barTop + barBottom) * 0.5;
    float barHalfHeight = (barTop - barBottom) * 0.5;

    float cornerRadius = min(cornerFraction * barHalfWidth, min(barHalfWidth, barHalfHeight));
    float2 halfExtents = float2(barHalfWidth, barHalfHeight) - cornerRadius;

    float2 local = float2(uv.x - slotCenterX, uv.y - barCenterY);
    float2 d = abs(local) - halfExtents;
    float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - cornerRadius;

    float aa = max(fwidth(dist), 0.0008);
    float alpha = 1.0 - smoothstep(0.0, aa, dist);

    float3 color = mix(float3(0.25, 0.55, 1.0), float3(1.0, 0.35, 0.65), uv.x);
    return float4(color, alpha);
}
