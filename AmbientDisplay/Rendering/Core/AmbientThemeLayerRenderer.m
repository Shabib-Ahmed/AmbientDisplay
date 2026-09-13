#import "AmbientThemeLayerRenderer.h"
#import "PackageManager.h"
#import "AmbientTextureCache.h"
#import "AmbientClockLayerRenderer.h"
#import "AmbientOverlayLayerRenderer.h"
#import "AmbientRecipeEffectRenderer.h"
#import "AmbientVisualizerEffectRenderer.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - AmbientThemeRenderContext

@implementation AmbientThemeRenderContext

- (instancetype)initWithThemeDirectoryURL:(NSURL *)themeDirectoryURL
                           audioDataSource:(nullable id<AmbientAudioDataSource>)audioDataSource
                              textureCache:(AmbientTextureCache *)textureCache {
    self = [super init];
    if (self) {
        _themeDirectoryURL = [themeDirectoryURL copy];
        _audioDataSource = audioDataSource;
        _textureCache = textureCache;
    }
    return self;
}

@end

#pragma mark - AmbientThemeLayerRendererFactory

@implementation AmbientThemeLayerRendererFactory

+ (nullable id<AmbientThemeLayerRenderer>)rendererForThemeLayer:(AmbientThemeLayer *)themeLayer
                                                          context:(AmbientThemeRenderContext *)context {
    Class rendererClass = [self rendererClassForThemeLayer:themeLayer];
    if (rendererClass == Nil) {
        NSLog(@"AmbientThemeLayerRendererFactory: no renderer registered for kind '%@'", themeLayer.kind);
        return nil;
    }

    id<AmbientThemeLayerRenderer> renderer = [rendererClass rendererWithThemeLayer:themeLayer context:context];
    if (renderer == nil) {
        // rendererWithThemeLayer:context: already logs the specific
        // reason (unrecognized type/malformed params) - this is just
        // the factory-level trace of which layer that was.
        NSLog(@"AmbientThemeLayerRendererFactory: %@ declined layer of kind '%@'",
              NSStringFromClass(rendererClass), themeLayer.kind);
    }
    return renderer;
}

// The kind/type -> concrete class mapping itself. Kept separate from
// rendererForThemeLayer:context: so the "which class handles this" logic
// is testable independent of actually instantiating anything.
+ (nullable Class)rendererClassForThemeLayer:(AmbientThemeLayer *)themeLayer {
    NSString *kind = themeLayer.kind;

    if ([kind isEqualToString:@"clock"]) {
        return [AmbientClockLayerRenderer class];
    }
    if ([kind isEqualToString:@"overlay"]) {
        return [AmbientOverlayLayerRenderer class];
    }
    if ([kind isEqualToString:@"effect"]) {
        // "type": "visualizer" is the one carve-out that gets an audio
        // data source; every other effect type (built-in shorthands
        // like particles/gradientWash/radialPulse/spriteAnimation, and
        // third-party "custom" recipes) goes through the recipe
        // renderer instead. See AmbientRecipeEffectRenderer.h /
        // AmbientVisualizerEffectRenderer.h.
        id typeValue = themeLayer.parameters[@"type"];
        if ([typeValue isKindOfClass:[NSString class]] &&
            [(NSString *)typeValue isEqualToString:@"visualizer"]) {
            return [AmbientVisualizerEffectRenderer class];
        }
        return [AmbientRecipeEffectRenderer class];
    }

    // Unrecognized kind - the forward-compatibility seam documented on
    // rendererWithThemeLayer:context: applies one level up here too: an
    // unknown kind just produces no renderer for that one layer, the
    // rest of the theme's layers are unaffected.
    return Nil;
}

@end

NS_ASSUME_NONNULL_END
