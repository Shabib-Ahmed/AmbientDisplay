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

    // Privilege rule (see AmbientAudioDataSource.h): only the visualizer is
    // ever handed an audio data source. Every other renderer - built-in or
    // custom - gets a context with the source stripped. The texture cache is
    // shared, so this costs nothing. New renderer classes are denied audio by
    // default; opt them in here explicitly if that's ever intended.
    AmbientThemeRenderContext *effectiveContext = context;
    if (rendererClass != [AmbientVisualizerEffectRenderer class] && context.audioDataSource != nil) {
        effectiveContext =
            [[AmbientThemeRenderContext alloc] initWithThemeDirectoryURL:context.themeDirectoryURL
                                                          audioDataSource:nil
                                                             textureCache:context.textureCache];
    }

    id<AmbientThemeLayerRenderer> renderer = [rendererClass rendererWithThemeLayer:themeLayer
                                                                             context:effectiveContext];
    if (renderer == nil) {
        NSLog(@"AmbientThemeLayerRendererFactory: %@ declined layer of kind '%@'",
              NSStringFromClass(rendererClass), themeLayer.kind);
    }
    return renderer;
}


+ (nullable Class)rendererClassForThemeLayer:(AmbientThemeLayer *)themeLayer {
    NSString *kind = themeLayer.kind;

    if ([kind isEqualToString:@"clock"]) {
        return [AmbientClockLayerRenderer class];
    }
    if ([kind isEqualToString:@"overlay"]) {
        return [AmbientOverlayLayerRenderer class];
    }
    if ([kind isEqualToString:@"effect"]) {
        id typeValue = themeLayer.parameters[@"type"];
        if ([typeValue isKindOfClass:[NSString class]] &&
            [(NSString *)typeValue isEqualToString:@"visualizer"]) {
            return [AmbientVisualizerEffectRenderer class];
        }
        return [AmbientRecipeEffectRenderer class];
    }
    return Nil;
}

@end

NS_ASSUME_NONNULL_END
