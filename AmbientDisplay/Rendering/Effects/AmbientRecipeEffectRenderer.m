#import "AmbientRecipeEffectRenderer.h"
#import "PackageManager.h"
#import "AmbientEffectRecipe.h"

NS_ASSUME_NONNULL_BEGIN

// STUB: handles every "kind": "effect" layer except "type": "visualizer"
// (matches the factory's dispatch rule), and produces a real transparent
// view so it's safe to insert into the compositor stack today. Still
// TODO, all per AmbientRecipeEffectRenderer.h:
//   - call [AmbientEffectRecipeLoader recipeForThemeLayer:themeDirectoryURL:]
//     to resolve the built-in shorthand or "custom" recipe file into an
//     AmbientEffectRecipe
//   - walk recipe.primitives and build a CALayer per primitive
//     (particle emitter / gradient wash / radial pulse / sprite
//     animation), keeping start/stop in sync with whatever's
//     animatable (emitter layers, CABasicAnimations, etc.)
@interface AmbientRecipeEffectRenderer ()
@property (nonatomic, strong) UIView *stubView;
@end

@implementation AmbientRecipeEffectRenderer

+ (nullable instancetype)rendererWithThemeLayer:(AmbientThemeLayer *)themeLayer
                                          context:(AmbientThemeRenderContext *)context {
    if (![themeLayer.kind isEqualToString:@"effect"]) {
        return nil;
    }
    id typeValue = themeLayer.parameters[@"type"];
    if ([typeValue isKindOfClass:[NSString class]] && [(NSString *)typeValue isEqualToString:@"visualizer"]) {
        // Visualizer is AmbientVisualizerEffectRenderer's territory.
        return nil;
    }

    AmbientRecipeEffectRenderer *renderer = [[AmbientRecipeEffectRenderer alloc] init];
    renderer.stubView = [[UIView alloc] init];
    renderer.stubView.backgroundColor = [UIColor clearColor];
    return renderer;
}

- (UIView *)view {
    return self.stubView;
}

- (void)start {
    // TODO: load the recipe via AmbientEffectRecipeLoader and build/
    // start CALayers for each primitive.
}

- (void)stop {
    // TODO: stop/remove the primitive CALayers.
}

@end

NS_ASSUME_NONNULL_END
