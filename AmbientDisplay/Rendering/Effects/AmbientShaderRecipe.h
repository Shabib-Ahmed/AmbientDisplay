#import <Foundation/Foundation.h>

@class AmbientThemeLayer;

NS_ASSUME_NONNULL_BEGIN

// Replaces AmbientEffectRecipe.h / AmbientEffectPrimitive. Where a recipe
// used to be a fixed-vocabulary stack of native drawing primitives
// (particle emitter, gradient wash, ...), it's now an ordered stack of
// shader passes. Primitives are gone - a "particles" look is now just a
// shader package, same mechanism as everything else.
@interface AmbientShaderPass : NSObject

// A package-relative path to shader source (.metal) or a precompiled
// .metallib - same resolution rules as AmbientTextureCache (contained
// within themeDirectoryURL, no "..", no absolute paths). There is no
// app-bundled "built-in" concept anymore: even the app's own default
// effects (bars, waveform, particles, gradient wash, radial pulse) are
// ordinary package-relative shaders shipped inside SamplePackages/
// sample-scene-package/Theme/Shaders/ - every theme, first-party or
// third-party, goes through this exact same path. The only thing that
// still lives in the app bundle is the shared fullscreen-quad VERTEX
// function (AmbientShaderCommon.metal) - see AmbientShaderLibraryCache.
@property (nonatomic, copy, readonly) NSString *shaderPath;

// This pass's param overrides -> AmbientShaderUniforms.params. Resolved
// to a vector_float4 by keys "x"/"y"/"z"/"w" (each an optional NSNumber,
// default 0) - see AmbientShaderEffectRenderer. Missing/non-dict params
// in the manifest just mean all-zero params, never a load failure.
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *params;

// Named inputs this pass wants bound, e.g. @[@"previous"],
// @[@"previous", @"audioLevels"], @[@"sourceVideo"]. Resolved by
// AmbientShaderEffectRenderer against whatever named textures it has
// available that frame, using the fixed binding-index table in
// AmbientShaderTypes.h ("previous", "original", "audioLevels",
// "sourceVideo"). An input name the renderer doesn't have a texture for
// that frame (e.g. "sourceVideo" - not wired up yet) is simply left
// unbound rather than failing the pass. Empty/nil = no texture inputs,
// uniforms only.
@property (nonatomic, copy, readonly, nullable) NSArray<NSString *> *inputs;

- (instancetype)initWithShaderPath:(NSString *)shaderPath
                             params:(NSDictionary<NSString *, id> *)params
                             inputs:(nullable NSArray<NSString *> *)inputs NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

// An ordered stack of passes, ping-ponged by AmbientShaderEffectRenderer.
// Pass count is fixed once loaded and capped at AmbientShaderMaxPassCount
// (see AmbientShaderTypes.h) here at load time, so a too-long recipe
// fails at parse time with a clear log rather than silently costing
// frame time.
@interface AmbientShaderRecipe : NSObject

@property (nonatomic, copy, readonly) NSArray<AmbientShaderPass *> *passes;

- (instancetype)initWithPasses:(NSArray<AmbientShaderPass *> *)passes NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

// Mirrors AmbientEffectRecipeLoader's job: turn a "kind": "effect" theme
// layer into a recipe. Manifest shape: an effect layer's parameters
// carry a top-level "shaders": [ {...}, {...} ] array, each entry
// shaped like:
//   { "path": "Shaders/Bars.metal", "params": {"x": 0.5}, "inputs": ["audioLevels"] }
// "path" is required; "params"/"inputs" are optional. There is no
// built-in-name fallback - every effect layer, including ones authored
// by this app's own sample package, must name its shader file(s)
// explicitly. See SamplePackages/sample-scene-package/manifest.json for
// what that looks like in practice.
@interface AmbientShaderRecipeLoader : NSObject

+ (nullable AmbientShaderRecipe *)recipeForThemeLayer:(AmbientThemeLayer *)themeLayer
                                      themeDirectoryURL:(NSURL *)themeDirectoryURL;

@end

NS_ASSUME_NONNULL_END
