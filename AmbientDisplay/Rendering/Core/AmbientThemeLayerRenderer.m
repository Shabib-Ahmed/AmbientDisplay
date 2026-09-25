#import "AmbientThemeLayerRenderer.h"
#import "PackageManager.h"
#import "AmbientTextureCache.h"
#import "AmbientClockLayerRenderer.h"
#import "AmbientShaderEffectRenderer.h"

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

    id<AmbientThemeLayerRenderer> renderer = [rendererClass rendererWithThemeLayer:themeLayer
                                                                             context:context];
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
    if ([kind isEqualToString:@"effect"]) {
        return [AmbientShaderEffectRenderer class];
    }
    return Nil;
}

@end

NS_ASSUME_NONNULL_END
