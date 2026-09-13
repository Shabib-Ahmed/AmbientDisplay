#import "AmbientVisualizerEffectRenderer.h"
#import "PackageManager.h"
#import "AmbientAudioDataSource.h"

NS_ASSUME_NONNULL_BEGIN

// STUB: handles "kind": "effect", "type": "visualizer" only (matches
// the factory's dispatch rule), and produces a real transparent view so
// it's safe to insert into the compositor stack today. Still TODO, per
// AmbientVisualizerEffectRenderer.h:
//   - read context.audioDataSource.latestSpectrumBins on a display-
//     synced timer/CADisplayLink
//   - draw bars/waveform from the bins (CAShapeLayer path updates or
//     similar) - this is the only renderer with audio access, so all
//     the audio-reactive drawing logic lives here and nowhere else
@interface AmbientVisualizerEffectRenderer ()
@property (nonatomic, strong) UIView *stubView;
@property (nonatomic, weak, nullable) id<AmbientAudioDataSource> audioDataSource;
@end

@implementation AmbientVisualizerEffectRenderer

+ (nullable instancetype)rendererWithThemeLayer:(AmbientThemeLayer *)themeLayer
                                          context:(AmbientThemeRenderContext *)context {
    if (![themeLayer.kind isEqualToString:@"effect"]) {
        return nil;
    }
    id typeValue = themeLayer.parameters[@"type"];
    if (![typeValue isKindOfClass:[NSString class]] || ![(NSString *)typeValue isEqualToString:@"visualizer"]) {
        return nil;
    }

    AmbientVisualizerEffectRenderer *renderer = [[AmbientVisualizerEffectRenderer alloc] init];
    renderer.audioDataSource = context.audioDataSource;
    renderer.stubView = [[UIView alloc] init];
    renderer.stubView.backgroundColor = [UIColor clearColor];
    return renderer;
}

- (UIView *)view {
    return self.stubView;
}

- (void)start {
    // TODO: start a CADisplayLink (or timer) reading
    // self.audioDataSource.latestSpectrumBins and drawing bars/waveform.
}

- (void)stop {
    // TODO: invalidate the display link / drawing timer.
}

@end

NS_ASSUME_NONNULL_END
