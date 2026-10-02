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

// Port target: old AmbientEffectPrimitiveTypeParticleEmitter, as handled
// by (deprecated) AmbientRecipeEffectRenderer's CALayer-based particle
// system. As flagged, there's no CAEmitterLayer equivalent to
// mechanically port - this is a genuine redesign: a hash-noise
// procedural particle field, one soft dot per grid cell, drifting
// upward and twinkling, entirely a function of time (no per-particle
// CPU-side state to manage).
//
// params.x -> density: grid cells per axis (particle count scales with
//   density^2) - keep modest (~8-16) on the old-phone hardware this
//   targets, since this shader is O(9) texture-free samples per pixel
//   (a 3x3 cell neighborhood) rather than O(1).
// params.y -> speed: upward drift rate.
// params.z -> hue (0...1).
// params.w -> size: particle radius as a fraction of one grid cell.
//
// Inputs: none for now (matching the "probably none unless
// audio-reactive density/speed is wanted" note) - a natural future
// extension, not assumed here.

static float ambient_hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

fragment float4 fragment_particles(VertexOut in [[stage_in]],
                                    constant AmbientShaderUniforms &uniforms [[buffer(AmbientShaderUniformBufferIndex)]]) {
    float density = max(uniforms.params.x, 1.0);
    float speed = uniforms.params.y;
    float hue = fract(uniforms.params.z);
    float size = clamp(uniforms.params.w, 0.02, 0.5);

    float aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1.0);
    float2 uv = in.uv * float2(aspect, 1.0);

    float3 color = ambient_hsv2rgb(float3(hue, 0.45, 1.0));
    float alpha = 0.0;

    // 3x3 neighborhood so a particle drifting across a cell boundary
    // doesn't get clipped at the edge of its own cell.
    for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
            float2 cell = floor(uv * density) + float2(ox, oy);
            float rnd = ambient_hash21(cell);
            float rnd2 = ambient_hash21(cell + 17.0);

            float phase = fract(uniforms.time * speed * (0.4 + rnd) + rnd2);
            float2 jitter = float2((rnd2 - 0.5) * 0.6, 0.5 - phase);
            float2 particleCenter = (cell + 0.5 + jitter) / density;

            float dist = length(uv - particleCenter);
            float radius = size / density;
            float twinkle = 0.5 + 0.5 * sin(uniforms.time * 2.0 + rnd * 6.2831853);
            float particleAlpha = (1.0 - smoothstep(radius * 0.3, radius, dist)) * twinkle;
            alpha = max(alpha, particleAlpha);
        }
    }

    return float4(color, alpha);
}
