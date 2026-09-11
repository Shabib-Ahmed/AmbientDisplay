#import <Foundation/Foundation.h>
#import "AmbientThemeLayerRenderer.h"

NS_ASSUME_NONNULL_BEGIN

// Renders "kind": "effect", "type": "visualizer" layers - bars/waveform
// driven by AmbientThemeRenderContext.audioDataSource. This is the only
// renderer in the whole layer system that ever reads audio data; no
// recipe primitive or custom effect has this capability, by design (see
// AmbientAudioDataSource.h).
@interface AmbientVisualizerEffectRenderer : NSObject <AmbientThemeLayerRenderer>

@end

NS_ASSUME_NONNULL_END
