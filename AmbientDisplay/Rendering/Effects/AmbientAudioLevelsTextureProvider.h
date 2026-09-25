#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "AmbientAudioDataSource.h"

NS_ASSUME_NONNULL_BEGIN

// Extracted from the old AmbientVisualizerEffectRenderer: resamples
// AmbientAudioDataSource's variable-length spectrum bins down to a
// fixed canonical width, applies the same attack/release smoothing the
// old renderer did (kAttackFactor / smoothing, fast rise / slow fall),
// and uploads the result into a small texture a fragment shader can
// sample. Kept native/non-shader on purpose - see prior discussion:
// this is "feel", not visuals, and every shader package would otherwise
// have to reimplement an envelope filter correctly.
//
// Ownership: for this restoration pass, each AmbientShaderEffectRenderer
// that has a pass declaring "audioLevels" creates and owns its own
// instance. Sharing one instance per theme (via AmbientThemeRenderContext)
// so multiple audio-reactive layers don't duplicate the resample/smooth
// work is a real optimization worth doing, but it means widening
// AmbientThemeRenderContext's contract, which touches
// AmbientThemeLayerCompositor too - left as a follow-up rather than
// bundled into getting clock/visualizer working again.
@interface AmbientAudioLevelsTextureProvider : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>)device
                 canonicalWidth:(NSUInteger)canonicalWidth NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, weak, nullable) id<AmbientAudioDataSource> audioDataSource;
@property (nonatomic, assign) CGFloat smoothing;    // default 0.85 (ported kDefaultSmoothing)
@property (nonatomic, assign) CGFloat sensitivity;  // default 1.0, clamped to 0...10 on set

// R32Float, canonicalWidth x 1. nil until the first -tick call.
@property (nonatomic, strong, readonly, nullable) id<MTLTexture> texture;

// Called once per display-link frame by whichever renderer(s) are
// driving audio-reactive layers this frame. Resamples + smooths +
// uploads via replaceRegion:mipmapLevel:withBytes:bytesPerRow: - TODO
// confirm this is cheap enough at 30fps on an old phone for
// canonicalWidth=64 (should be trivial, but measure, don't assume).
- (void)tick;

@end

NS_ASSUME_NONNULL_END
