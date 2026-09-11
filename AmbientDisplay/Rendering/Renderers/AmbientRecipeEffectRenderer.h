#import <Foundation/Foundation.h>
#import "AmbientThemeLayerRenderer.h"

NS_ASSUME_NONNULL_BEGIN

// Renders every "kind": "effect" layer except "type": "visualizer" -
// that is, both the other built-ins (particles, gradientWash, radialPulse,
// spriteAnimation) and "type": "custom" recipes from third-party
// packages. All of these go through AmbientEffectRecipeLoader to become
// an AmbientEffectRecipe first; this renderer just walks the resulting
// primitives and builds CALayers for them. Never receives an audio data
// source - only AmbientVisualizerEffectRenderer does.
@interface AmbientRecipeEffectRenderer : NSObject <AmbientThemeLayerRenderer>

@end

NS_ASSUME_NONNULL_END
