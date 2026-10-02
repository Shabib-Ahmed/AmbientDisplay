#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Implemented by AudioEngineManager. Deliberately the *only* thing any
// effect renderer can see of the audio pipeline.
@protocol AmbientAudioDataSource <NSObject>

@property (nonatomic, readonly) NSUInteger spectrumBinCount;

// Updated continuously off the audio tap; nil until the first buffer has
// been processed. Safe to read from any thread.
@property (atomic, copy, readonly, nullable) NSArray<NSNumber *> *latestSpectrumBins;

@end

NS_ASSUME_NONNULL_END
