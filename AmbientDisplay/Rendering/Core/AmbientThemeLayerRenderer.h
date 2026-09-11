#import <UIKit/UIKit.h>
#import "AmbientAudioDataSource.h"

@class AmbientThemeLayer;
@class AmbientTextureCache;

NS_ASSUME_NONNULL_BEGIN

// Bundles everything a renderer might need to build itself from a theme
// layer. Every renderer receives the same context regardless of what it
// actually uses - a clock ignores textureCache and audioDataSource
// entirely, only the visualizer built-in touches audioDataSource, only
// recipe-based effects touch textureCache. One context is built per
// loadTheme: call and discarded with the renderers it produced, so a
// texture cache never outlives the theme it was decoded for.
@interface AmbientThemeRenderContext : NSObject

@property (nonatomic, copy, readonly) NSURL *themeDirectoryURL;
@property (nonatomic, weak, readonly, nullable) id<AmbientAudioDataSource> audioDataSource;
@property (nonatomic, strong, readonly) AmbientTextureCache *textureCache;

- (instancetype)initWithThemeDirectoryURL:(NSURL *)themeDirectoryURL
                          audioDataSource:(nullable id<AmbientAudioDataSource>)audioDataSource
                              textureCache:(AmbientTextureCache *)textureCache NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

// Implemented by every concrete layer renderer (visualizer, recipe-based
// effects, clock, overlay, and any kind added later). One instance per
// entry in AmbientTheme.layers, torn down and rebuilt from scratch on
// every theme switch - no update-in-place, matching the app's existing
// hard-cut philosophy for playlist and background-video switches.
@protocol AmbientThemeLayerRenderer <NSObject>

// Returns nil (logged) if this renderer doesn't recognize the layer's
// kind/type, or if required parameters are missing/malformed - never
// throws. This is the forward-compatibility seam: a manifest referencing
// a kind/type newer than this build understands just fails to produce a
// renderer for that one layer, the rest of the theme is unaffected.
+ (nullable instancetype)rendererWithThemeLayer:(AmbientThemeLayer *)themeLayer
                                          context:(AmbientThemeRenderContext *)context;

// The view to insert into the compositor's stack at this renderer's
// position. Must have a transparent background so lower layers stay
// visible. Sized to fill the compositor by whoever owns it - a renderer
// should not assume responsibility for its own frame.
@property (nonatomic, strong, readonly) UIView *view;

- (void)start;
- (void)stop;

@end

// Owns the kind/type -> concrete renderer class mapping. This is the one
// place that needs to know about every renderer class that exists;
// nothing else in the layer pipeline does.
@interface AmbientThemeLayerRendererFactory : NSObject

+ (nullable id<AmbientThemeLayerRenderer>)rendererForThemeLayer:(AmbientThemeLayer *)themeLayer
                                                          context:(AmbientThemeRenderContext *)context;

@end

NS_ASSUME_NONNULL_END
