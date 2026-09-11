#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@class PackageManager;
@class AudioEngineManager;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RepeatMode) {
    RepeatModeOff = 0,
    RepeatModeOne,
    RepeatModeAll,
};

@protocol AudioEngineManagerDelegate <NSObject>

@optional
- (void)audioEngine:(AudioEngineManager *)engine
    didChangeTrackURL:(nullable NSURL *)trackURL
             metadata:(nullable NSDictionary<NSString *, id> *)metadata;

- (void)audioEngineDidReachEndOfQueue:(AudioEngineManager *)engine;

@end

@interface AudioEngineManager : NSObject

@property (nonatomic, weak, nullable) id<AudioEngineManagerDelegate> delegate;

- (instancetype)initWithPackageManager:(PackageManager *)packageManager NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, assign) RepeatMode repeatMode;
@property (nonatomic, assign, getter=isShuffleEnabled) BOOL shuffleEnabled;

@property (nonatomic, readonly, nullable) NSURL *currentTrackURL;
@property (nonatomic, readonly) NSUInteger currentTrackIndex;
@property (nonatomic, readonly, getter=isPlaying) BOOL playing;

@property (nonatomic, readonly) NSUInteger spectrumBinCount;

@property (atomic, copy, readonly, nullable) NSArray<NSNumber *> *latestSpectrumBins;

- (void)play;
- (void)pause;
- (void)togglePlayPause;
- (void)skipToNextTrack;
- (void)skipToPreviousTrack;
- (void)skipToTrackAtIndex:(NSUInteger)index;
- (void)reloadActivePlaylistAndHardCut;

@end

NS_ASSUME_NONNULL_END
