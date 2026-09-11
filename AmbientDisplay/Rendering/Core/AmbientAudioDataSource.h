#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Implemented by AudioEngineManager. Deliberately the *only* thing any
// effect renderer can see of the audio pipeline, and only the visualizer
// effect renderer is ever handed one - every other effect (built-in or
// custom/third-party) never receives an audio data source at all, so
// audio-reactivity is impossible outside this one privileged built-in.
@protocol AmbientAudioDataSource <NSObject>

@property (nonatomic, readonly) NSUInteger spectrumBinCount;

// Updated continuously off the audio tap; nil until the first buffer has
// been processed. Safe to read from any thread.
@property (atomic, copy, readonly, nullable) NSArray<NSNumber *> *latestSpectrumBins;

@end

NS_ASSUME_NONNULL_END
