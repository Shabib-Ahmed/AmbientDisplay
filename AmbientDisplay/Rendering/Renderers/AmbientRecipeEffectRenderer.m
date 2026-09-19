#import "AmbientRecipeEffectRenderer.h"
#import "PackageManager.h"
#import "AmbientEffectRecipe.h"

NS_ASSUME_NONNULL_BEGIN


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
