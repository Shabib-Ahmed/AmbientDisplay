#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

// The shader-side analog of AmbientTextureCache: the one place that
// turns a package-relative shader reference (.metal source path, or
// .metallib path) into a compiled MTLRenderPipelineState, and caches
// the result for the lifetime of the theme it was built for. Every
// AmbientShaderEffectRenderer pass goes through this rather than
// calling MTLDevice compile methods directly.
//
// There is no "built-in" branch here anymore - the app's own default
// effects are ordinary shaders shipped inside SamplePackages/
// sample-scene-package/Theme/Shaders/, resolved through the exact same
// containment-checked path as any third-party package's shaders. The
// ONE thing that IS still app-bundled is the shared fullscreen-quad
// VERTEX function (compiled from Rendering/Shaders/AmbientShaderCommon.metal
// into the app's default MTLLibrary at build time) - every pipeline
// state built here pairs that precompiled vertex function with a
// runtime-compiled, package-supplied fragment function. Metal allows
// mixing functions from different MTLLibrary instances in one
// MTLRenderPipelineDescriptor as long as they share a device, so this
// costs nothing extra.
//
// Mirrors AmbientTextureCache's containment rules for the
// package-relative shader source/metallib path (no "..", no absolute
// path, resolved within themeDirectoryURL, size cap before compiling).
// Threat model, as implemented: compiling arbitrary shader source from
// a package can cost GPU workload / cause a DoS via a pathological
// shader, but Metal source has no filesystem/network/syscall access, so
// nothing worse is believed possible. This is still an assumption
// carried forward from the original design discussion, not something
// independently verified against Metal compiler internals - worth
// another look before a non-first-party package is ever loaded in
// production.
@interface AmbientShaderLibraryCache : NSObject

// vertexLibrary: the app's precompiled default MTLLibrary, containing
// ambient_fullscreen_vertex. Passed in rather than loaded here so this
// class stays purely about the package-shader half of the contract.
- (instancetype)initWithDevice:(id<MTLDevice>)device
                 vertexLibrary:(id<MTLLibrary>)vertexLibrary
             themeDirectoryURL:(NSURL *)themeDirectoryURL
                   pixelFormat:(MTLPixelFormat)pixelFormat NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Returns nil (logged) on compile failure - a bad/unsupported shader in
// one package should drop that one layer, not crash the app or block
// every other layer from rendering. Cached by resolved shaderPath so
// multiple passes/layers reusing one shader only compile it once.
- (nullable id<MTLRenderPipelineState>)pipelineStateForShaderPath:(NSString *)shaderPath;

@end

NS_ASSUME_NONNULL_END
