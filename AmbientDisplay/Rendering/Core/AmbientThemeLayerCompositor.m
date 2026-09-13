#import "AmbientThemeLayerCompositor.h"
#import "AmbientThemeLayerRenderer.h"
#import "AmbientTextureCache.h"
#import "PackageManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface AmbientThemeLayerCompositor ()

@property (nonatomic, weak, nullable) id<AmbientAudioDataSource> audioDataSource;
@property (nonatomic, copy) NSArray<id<AmbientThemeLayerRenderer>> *activeRenderers;

@end

@implementation AmbientThemeLayerCompositor

- (instancetype)initWithFrame:(CGRect)frame
               audioDataSource:(nullable id<AmbientAudioDataSource>)audioDataSource {
    self = [super initWithFrame:frame];
    if (self) {
        _audioDataSource = audioDataSource;
        _activeRenderers = @[];
        self.backgroundColor = [UIColor clearColor];
        // Ambient display - nothing in the current renderer set is
        // interactive, and package-supplied overlay content is
        // deliberately locked down (no JS, no navigation) rather than
        // meant to receive touches.
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)loadTheme:(nullable AmbientTheme *)theme {
    [self tearDownActiveRenderers];

    if (theme == nil) {
        return;
    }

    AmbientTextureCache *textureCache =
        [[AmbientTextureCache alloc] initWithThemeDirectoryURL:theme.themeDirectoryURL];
    AmbientThemeRenderContext *context =
        [[AmbientThemeRenderContext alloc] initWithThemeDirectoryURL:theme.themeDirectoryURL
                                                       audioDataSource:self.audioDataSource
                                                          textureCache:textureCache];

    NSMutableArray<id<AmbientThemeLayerRenderer>> *renderers =
        [NSMutableArray arrayWithCapacity:theme.layers.count];

    // theme.layers[0] is built (and added) first, so it lands at the
    // bottom of the stack, directly above the background video; each
    // subsequent entry's view is added on top of the ones before it via
    // addSubview:, which is exactly the ordering contract this method
    // documents on AmbientThemeLayerCompositor.h.
    for (AmbientThemeLayer *themeLayer in theme.layers) {
        id<AmbientThemeLayerRenderer> renderer =
            [AmbientThemeLayerRendererFactory rendererForThemeLayer:themeLayer context:context];
        if (renderer == nil) {
            // Logged inside the factory - an unrecognized/malformed
            // layer is simply skipped, the rest of the theme is
            // unaffected.
            continue;
        }

        renderer.view.frame = self.bounds;
        renderer.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:renderer.view];
        [renderer start];

        [renderers addObject:renderer];
    }

    self.activeRenderers = renderers;
}

- (void)tearDownActiveRenderers {
    // Same hard-cut philosophy as playlist/background-video switching:
    // no diffing against the previous theme, just stop and remove
    // everything before anything new gets built.
    for (id<AmbientThemeLayerRenderer> renderer in self.activeRenderers) {
        [renderer stop];
        [renderer.view removeFromSuperview];
    }
    self.activeRenderers = @[];
}

- (void)dealloc {
    for (id<AmbientThemeLayerRenderer> renderer in _activeRenderers) {
        [renderer stop];
    }
}

@end

NS_ASSUME_NONNULL_END
