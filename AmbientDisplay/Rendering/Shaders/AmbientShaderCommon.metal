#include <metal_stdlib>
using namespace metal;

// Shares AmbientShaderUniforms with the ObjC side by #including the same
// header both sides use - see that file for the binding-index
// convention every pass (including this app's own sample shaders) is
// expected to follow. Metal's compiler accepts a plain C header here as
// long as it sticks to C/simd types, which AmbientShaderTypes.h does.
//
// Relative path, not a bare quoted name: this file lives in
// Rendering/Shaders/, AmbientShaderTypes.h lives in Rendering/Effects/ -
// a quoted #include only auto-resolves against files in the SAME
// directory as the includer, so the path has to be spelled out rather
// than relying on the target's Header Search Paths picking it up (metal
// and clang don't reliably share the same effective search path set for
// that setting).
#include "../Effects/AmbientShaderTypes.h"

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Every pass in every recipe uses this SAME vertex function - only the
// fragment function varies per shader/pass. Draw with
// drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3
// (no vertex/index buffer needed - positions are synthesized from
// vertex_id below, the standard "oversized fullscreen triangle" trick:
// a single triangle with vertices at (-1,-1), (3,-1), (-1,3) fully
// covers NDC space [-1,1]^2, and the GPU clips the overhang outside the
// viewport for free - no seam, no need for a second triangle).
vertex VertexOut ambient_fullscreen_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    VertexOut out;
    float2 p = positions[vertexID];
    out.position = float4(p, 0.0, 1.0);
    // uv only needs to be correct over the visible [-1,1] region; the
    // overhang (uv outside [0,1]) is clipped before any fragment shader
    // sees it, so no clamping is needed here.
    out.uv = (p + 1.0) * 0.5;
    return out;
}

// Fragment-function naming convention (resolves the "how does the cache
// find *the* fragment function" TODO): each package shader file
// declares exactly one fragment_* function, named "fragment_" followed
// by its .metal file's basename lowercased - e.g. Bars.metal must
// define `fragment_bars`, GradientWash.metal must define
// `fragment_gradientwash`. AmbientShaderLibraryCache derives this name
// from shaderPath's last path component; see that file.
//
// This file must be added to the Xcode target's Metal compile sources
// (it's the one shader source that ships in the app bundle rather than
// a package - see AmbientShaderLibraryCache.h for why).
