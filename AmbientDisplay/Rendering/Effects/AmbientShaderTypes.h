#ifndef AmbientShaderTypes_h
#define AmbientShaderTypes_h

// Included from BOTH Objective-C (.m) and Metal (.metal) source, so this
// file must stick to types that mean the same thing in both: simd types,
// no ObjC classes, no Metal-only keywords. This is the entire contract
// between AmbientShaderEffectRenderer and every pass's fragment shader.
//
// AmbientShaderCommon.metal #includes this file directly rather than
// re-declaring the struct, so there is exactly one definition of
// AmbientShaderUniforms - no drift possible between the ObjC and Metal
// sides.

#include <simd/simd.h>

typedef struct {
    float time;                // seconds since the renderer's -start call
    vector_float2 resolution;  // current drawable size in points
    vector_float4 params;      // this pass's params dict -> (x, y, z, w); meaning defined by each shader
    float sensitivity;         // theme layer's "sensitivity" param, native-parsed, passed through as-is
} AmbientShaderUniforms;

// Binding convention (resolves the "where does index N come from" TODO):
// every pass uses buffer(0) for uniforms, and named texture inputs bind
// to fixed indices by name. A pass's "inputs" array (see
// AmbientShaderRecipe.h) is resolved against this table by
// AmbientShaderEffectRenderer; a shader simply declares
// [[texture(AmbientShaderTexturePreviousIndex)]] etc. and trusts the
// renderer to have bound (or left unbound) that slot per-pass.
#define AmbientShaderUniformBufferIndex 0

#define AmbientShaderTexturePreviousIndex     0  // this layer's own prior pass output (nil on pass 0)
#define AmbientShaderTextureOriginalIndex     1  // reserved: pre-effect source content (not yet wired - see TODO below)
#define AmbientShaderTextureAudioLevelsIndex  2  // AmbientAudioLevelsTextureProvider.texture
#define AmbientShaderTextureSourceVideoIndex  3  // reserved: background video frame (not yet wired - see TODO below)
// Package-declared named textures (via AmbientTextureCache) start here,
// once that's wired up - not needed for clock/visualizer restoration.
#define AmbientShaderTexturePackageBaseIndex  4

// TODO: "original" and "sourceVideo" are reserved slots only - nothing
// currently binds a texture there. Neither clock nor the visualizer
// shaders (Bars/Waveform) need them, so this is fine for the current
// restoration pass; wiring them up means piping the background video's
// current frame into AmbientThemeRenderContext, which is out of scope
// here (tracked separately, not needed until a package actually wants
// to sample the video itself).

// Pass count is capped since each pass is a full-screen fill and old-GPU
// frame time adds up fast. Shared by AmbientShaderRecipe (enforced at
// parse time) and AmbientShaderEffectRenderer (defensive re-check) so
// there's exactly one number to change.
#define AmbientShaderMaxPassCount 4

#endif /* AmbientShaderTypes_h */
