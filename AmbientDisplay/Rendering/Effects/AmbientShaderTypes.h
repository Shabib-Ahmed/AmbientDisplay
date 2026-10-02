#ifndef AmbientShaderTypes_h
#define AmbientShaderTypes_h

// Included from both Objective-C and Metal source: use only types that mean
// the same in both (simd types; no ObjC classes, no Metal-only keywords).


#include <simd/simd.h>

typedef struct {
    float time;                // seconds since the renderer's -start call
    vector_float2 resolution;  // current drawable size in points
    vector_float4 params;      // this pass's params dict -> (x, y, z, w); meaning defined by each shader
    float sensitivity;         // theme layer's "sensitivity" param, native-parsed, passed through as-is
} AmbientShaderUniforms;

#define AmbientShaderUniformBufferIndex 0

#define AmbientShaderTexturePreviousIndex     0  // this layer's own prior pass output (nil on pass 0)
#define AmbientShaderTextureOriginalIndex     1  // reserved: pre-effect source content (not yet wired - see TODO below)
#define AmbientShaderTextureAudioLevelsIndex  2  // AmbientAudioLevelsTextureProvider.texture
#define AmbientShaderTextureSourceVideoIndex  3  // reserved: background video frame (not yet wired - see TODO below)
#define AmbientShaderTexturePackageBaseIndex  4

#define AmbientShaderMaxPassCount 4

#endif /* AmbientShaderTypes_h */
