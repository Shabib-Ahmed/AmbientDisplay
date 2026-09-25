#import <Foundation/Foundation.h>
#import "AmbientThemeLayerRenderer.h"

NS_ASSUME_NONNULL_BEGIN

// Replaces AmbientRecipeEffectRenderer AND AmbientVisualizerEffectRenderer.
// Renders every "kind": "effect" layer, full stop - there is no more
// per-effect-type native class. What a layer looks like is entirely a
// function of the shader(s) its AmbientShaderRecipe names; this class
// just runs the pipeline:
//
//   for each pass in recipe.passes:
//     bind uniforms (time, resolution, pass.params, sensitivity)
//     bind named input textures the pass declared (previous/original/
//       audioLevels/sourceVideo/package textures via AmbientTextureCache)
//     draw fullscreen quad into: drawable (last pass) or the other
//       ping-pong target (all other passes)
//
// Audio reactivity is no longer a privileged built-in - see
// AmbientAudioDataSource.h, updated to match: ANY pass that declares
// "audioLevels" as an input gets it, not just one hardcoded visualizer
// class.
@interface AmbientShaderEffectRenderer : NSObject <AmbientThemeLayerRenderer>

@end

NS_ASSUME_NONNULL_END
