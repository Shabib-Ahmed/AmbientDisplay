#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Implemented by AudioEngineManager. Deliberately the *only* thing any
// effect renderer can see of the audio pipeline. Audio reactivity is NOT
// a privileged built-in: every "kind": "effect" layer's context carries
// the same audio data source, and any shader pass in any effect layer
// can opt in by declaring "audioLevels" as one of its inputs (see
// AmbientShaderRecipe.h / AmbientShaderTypes.h) - there is no longer a
// single hardcoded class that's the only one allowed to see this.
@protocol AmbientAudioDataSource <NSObject>

@property (nonatomic, readonly) NSUInteger spectrumBinCount;

// Updated continuously off the audio tap; nil until the first buffer has
// been processed. Safe to read from any thread.
@property (atomic, copy, readonly, nullable) NSArray<NSNumber *> *latestSpectrumBins;

@end

NS_ASSUME_NONNULL_END
