#import "AudioEngineManager.h"
#import "PackageManager.h"
#import <Accelerate/Accelerate.h>

static NSUInteger const kSpectrumBinCount = 32;
static NSUInteger const kFFTFrameSize = 2048;
static NSUInteger const kFFTLog2n = 11;

@interface AudioEngineManager ()

@property (nonatomic, strong) PackageManager *packageManager;

@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *playerNode;

@property (nonatomic, copy) NSArray<NSURL *> *queueURLs;
@property (nonatomic, assign) NSUInteger queueIndex;

// The playlistId currently loaded into queueURLs. Used to detect the
// redundant reload that fires when resolveActivePlaylistWithFallback picks
// a default playlist: setting activePlaylistId re-triggers our own KVO,
// but by then we've already loaded that exact playlist, so there's nothing
// further to do.
@property (nonatomic, copy, nullable) NSString *loadedPlaylistId;

@property (nonatomic, assign) BOOL playing;

@property (atomic, copy, readwrite, nullable) NSArray<NSNumber *> *latestSpectrumBins;

// FFT setup - created once, reused for the lifetime of the engine.
@property (nonatomic, assign) FFTSetup fftSetup;
@property (nonatomic, assign) float *hannWindow;

@end

@implementation AudioEngineManager

#pragma mark - Init / Teardown

- (instancetype)initWithPackageManager:(PackageManager *)packageManager {
    NSLog(@"[AudioEngineManager] initWithPackageManager: called");
    self = [super init];
    if (self) {
        _packageManager = packageManager;
        _repeatMode = RepeatModeAll;
        _shuffleEnabled = NO;
        _queueURLs = @[];
        _queueIndex = 0;

        [self setUpAudioEngine];
        [self setUpFFT];

        [self.packageManager addObserver:self
                               forKeyPath:@"activePlaylistId"
                                  options:0
                                  context:NULL];

        [self reloadActivePlaylistAndHardCut];
    }
    return self;
}

- (void)dealloc {
    [self.packageManager removeObserver:self forKeyPath:@"activePlaylistId"];
    [self tearDownTap];
    if (_fftSetup) {
        vDSP_destroy_fftsetup(_fftSetup);
    }
    if (_hannWindow) {
        free(_hannWindow);
    }
}

- (void)setUpAudioEngine {
    self.engine = [[AVAudioEngine alloc] init];
    self.playerNode = [[AVAudioPlayerNode alloc] init];
    [self.engine attachNode:self.playerNode];

    AVAudioFormat *format = [self.engine.mainMixerNode outputFormatForBus:0];
    [self.engine connect:self.playerNode to:self.engine.mainMixerNode format:format];

    NSError *error = nil;
    if (![self.engine startAndReturnError:&error]) {
        NSLog(@"AudioEngineManager: failed to start AVAudioEngine: %@", error);
    }

    [self installTap];
}

- (void)setUpFFT {
    _fftSetup = vDSP_create_fftsetup(kFFTLog2n, kFFTRadix2);
    _hannWindow = (float *)malloc(sizeof(float) * kFFTFrameSize);
    vDSP_hann_window(_hannWindow, kFFTFrameSize, vDSP_HANN_NORM);
}

#pragma mark - KVO (hard-cut on playlist change)

- (void)observeValueForKeyPath:(nullable NSString *)keyPath
                       ofObject:(nullable id)object
                         change:(nullable NSDictionary<NSKeyValueChangeKey,id> *)change
                        context:(nullable void *)context {
    if (object == self.packageManager && [keyPath isEqualToString:@"activePlaylistId"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadActivePlaylistAndHardCut];
        });
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - Playlist loading / hard cut

- (void)reloadActivePlaylistAndHardCut {
    // resolveActivePlaylistWithFallback: defaults to the first installed
    // playlist when nothing has been explicitly chosen, and only returns
    // nil when there's genuinely no playlist package installed. Note this
    // may call setActivePlaylistId: under us, which re-triggers this method
    // via our own KVO observation - the loadedPlaylistId check below makes
    // that redundant second call a no-op.
    AmbientPlaylist *playlist = [self.packageManager resolveActivePlaylistWithFallback];

    if (playlist && [playlist.playlistId isEqualToString:self.loadedPlaylistId] && self.queueURLs.count > 0) {
        return;
    }

    [self.playerNode stop];
    self.playing = NO;

    NSArray<NSURL *> *trackURLs = playlist.trackURLs ?: @[];

    NSLog(@"[AudioEngineManager] reloadActivePlaylistAndHardCut: activePlaylistId=%@ trackCount=%lu",
          playlist.playlistId, (unsigned long)trackURLs.count);

    self.loadedPlaylistId = playlist.playlistId;
    self.queueURLs = self.shuffleEnabled ? [self shuffledArray:trackURLs] : trackURLs;
    self.queueIndex = 0;

    if (self.queueURLs.count > 0) {
        [self scheduleAndPlayCurrentIndex];
    } else {
        [self notifyTrackChangeToNil];
    }
}

- (NSArray<NSURL *> *)shuffledArray:(NSArray<NSURL *> *)array {
    NSMutableArray<NSURL *> *mutable = [array mutableCopy];
    for (NSUInteger i = mutable.count; i > 1; i--) {
        NSUInteger j = arc4random_uniform((uint32_t)i);
        [mutable exchangeObjectAtIndex:i - 1 withObjectAtIndex:j];
    }
    return mutable;
}

#pragma mark - Transport

- (void)play {
    if (self.queueURLs.count == 0) return;
    [self.playerNode play];
    self.playing = YES;
}

- (void)pause {
    [self.playerNode pause];
    self.playing = NO;
}

- (void)togglePlayPause {
    self.playing ? [self pause] : [self play];
}

- (void)skipToNextTrack {
    [self advanceQueueIndexForward:YES userInitiated:YES];
}

- (void)skipToPreviousTrack {
    [self advanceQueueIndexForward:NO userInitiated:YES];
}

- (void)skipToTrackAtIndex:(NSUInteger)index {
    if (index >= self.queueURLs.count) return;
    self.queueIndex = index;
    [self scheduleAndPlayCurrentIndex];
}

- (NSURL *)currentTrackURL {
    if (self.queueIndex < self.queueURLs.count) {
        return self.queueURLs[self.queueIndex];
    }
    return nil;
}

- (NSUInteger)currentTrackIndex {
    return self.queueIndex;
}

- (NSUInteger)spectrumBinCount {
    return kSpectrumBinCount;
}

#pragma mark - Track scheduling

- (void)scheduleAndPlayCurrentIndex {
    NSURL *url = self.currentTrackURL;
    if (!url) {
        [self notifyTrackChangeToNil];
        return;
    }

    NSError *error = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
    if (!file) {
        NSLog(@"AudioEngineManager: failed to open %@: %@", url, error);
        [self advanceQueueIndexForward:YES userInitiated:NO];
        return;
    }

    [self.playerNode stop];

    __weak typeof(self) weakSelf = self;
    [self.playerNode scheduleFile:file
                            atTime:nil
                 completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack
                 completionHandler:^(AVAudioPlayerNodeCompletionCallbackType callbackType) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleTrackFinished];
        });
    }];

    [self.playerNode play];
    self.playing = YES;

    NSLog(@"[AudioEngineManager] now playing (%lu/%lu): %@",
          (unsigned long)self.queueIndex + 1, (unsigned long)self.queueURLs.count, url.lastPathComponent);

    [self notifyTrackChangeForURL:url];
    [self extractID3TagsForURL:url];
}

- (void)handleTrackFinished {
    if (!self.playing) return; // stopped manually, not a natural completion
    [self advanceQueueIndexForward:YES userInitiated:NO];
}

- (void)advanceQueueIndexForward:(BOOL)forward userInitiated:(BOOL)userInitiated {
    if (self.queueURLs.count == 0) return;

    if (self.repeatMode == RepeatModeOne && !userInitiated) {
        [self scheduleAndPlayCurrentIndex];
        return;
    }

    NSInteger newIndex = (NSInteger)self.queueIndex + (forward ? 1 : -1);

    if (newIndex >= (NSInteger)self.queueURLs.count) {
        if (self.repeatMode == RepeatModeAll) {
            newIndex = 0;
        } else {
            self.playing = NO;
            if ([self.delegate respondsToSelector:@selector(audioEngineDidReachEndOfQueue:)]) {
                [self.delegate audioEngineDidReachEndOfQueue:self];
            }
            return;
        }
    } else if (newIndex < 0) {
        newIndex = self.repeatMode == RepeatModeAll ? (NSInteger)self.queueURLs.count - 1 : 0;
    }

    self.queueIndex = (NSUInteger)newIndex;
    [self scheduleAndPlayCurrentIndex];
}

#pragma mark - ID3 metadata (async)

- (void)extractID3TagsForURL:(NSURL *)url {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        AVAsset *asset = [AVAsset assetWithURL:url];
        NSMutableDictionary<NSString *, id> *metadata = [NSMutableDictionary dictionary];

        for (AVMetadataItem *item in asset.commonMetadata) {
            if ([item.commonKey isEqualToString:AVMetadataCommonKeyTitle] && item.value) {
                metadata[@"title"] = item.value;
            } else if ([item.commonKey isEqualToString:AVMetadataCommonKeyArtist] && item.value) {
                metadata[@"artist"] = item.value;
            } else if ([item.commonKey isEqualToString:AVMetadataCommonKeyArtwork] && item.value) {
                metadata[@"artwork"] = item.value;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            // Guard against a stale async result landing after another skip.
            if (![strongSelf.currentTrackURL isEqual:url]) return;
            if ([strongSelf.delegate respondsToSelector:@selector(audioEngine:didChangeTrackURL:metadata:)]) {
                [strongSelf.delegate audioEngine:strongSelf didChangeTrackURL:url metadata:metadata];
            }
        });
    });
}

- (void)notifyTrackChangeForURL:(NSURL *)url {
    if ([self.delegate respondsToSelector:@selector(audioEngine:didChangeTrackURL:metadata:)]) {
        [self.delegate audioEngine:self didChangeTrackURL:url metadata:nil];
    }
}

- (void)notifyTrackChangeToNil {
    if ([self.delegate respondsToSelector:@selector(audioEngine:didChangeTrackURL:metadata:)]) {
        [self.delegate audioEngine:self didChangeTrackURL:nil metadata:nil];
    }
}

#pragma mark - PCM Tap / DSP

- (void)installTap {
    AVAudioFormat *tapFormat = [self.engine.mainMixerNode outputFormatForBus:0];
    __weak typeof(self) weakSelf = self;

    [self.engine.mainMixerNode installTapOnBus:0
                                     bufferSize:(AVAudioFrameCount)kFFTFrameSize
                                         format:tapFormat
                                          block:^(AVAudioPCMBuffer * _Nonnull buffer, AVAudioTime * _Nonnull when) {
        [weakSelf processPCMBuffer:buffer];
    }];
}

- (void)tearDownTap {
    [self.engine.mainMixerNode removeTapOnBus:0];
}

- (void)processPCMBuffer:(AVAudioPCMBuffer *)buffer {
    if (!self.fftSetup || buffer.frameLength < kFFTFrameSize) return;

    float *samples = buffer.floatChannelData[0];
    NSUInteger n = kFFTFrameSize;

    float windowed[kFFTFrameSize];
    vDSP_vmul(samples, 1, self.hannWindow, 1, windowed, 1, n);

    float realp[kFFTFrameSize / 2];
    float imagp[kFFTFrameSize / 2];
    DSPSplitComplex splitComplex = { .realp = realp, .imagp = imagp };

    vDSP_ctoz((DSPComplex *)windowed, 2, &splitComplex, 1, n / 2);
    vDSP_fft_zrip(self.fftSetup, &splitComplex, 1, kFFTLog2n, FFT_FORWARD);

    float magnitudes[kFFTFrameSize / 2];
    vDSP_zvmags(&splitComplex, 1, magnitudes, 1, n / 2);

    NSArray<NSNumber *> *bins = [self logDownsampleMagnitudes:magnitudes count:n / 2];


    self.latestSpectrumBins = bins;
}

- (NSArray<NSNumber *> *)logDownsampleMagnitudes:(float *)magnitudes count:(NSUInteger)count {
    NSMutableArray<NSNumber *> *bins = [NSMutableArray arrayWithCapacity:kSpectrumBinCount];

    double minBin = 1.0;
    double maxBin = (double)(count - 1);
    double logMin = log2(minBin);
    double logMax = log2(maxBin);

    float peak = FLT_MIN;

    float rawBins[kSpectrumBinCount];
    for (NSUInteger b = 0; b < kSpectrumBinCount; b++) {
        double t0 = logMin + (logMax - logMin) * ((double)b / kSpectrumBinCount);
        double t1 = logMin + (logMax - logMin) * ((double)(b + 1) / kSpectrumBinCount);
        NSUInteger start = MAX((NSUInteger)round(pow(2.0, t0)), 1);
        NSUInteger end = MIN((NSUInteger)round(pow(2.0, t1)), count - 1);
        if (end <= start) end = start + 1;

        float sum = 0;
        NSUInteger sampled = 0;
        for (NSUInteger i = start; i < end && i < count; i++) {
            sum += magnitudes[i];
            sampled++;
        }
        float avg = sampled > 0 ? sum / (float)sampled : 0.f;
        float value = sqrtf(avg);
        rawBins[b] = value;
        if (value > peak) peak = value;
    }

    for (NSUInteger b = 0; b < kSpectrumBinCount; b++) {
        float normalized = peak > 0.f ? rawBins[b] / peak : 0.f;
        [bins addObject:@(normalized)];
    }

    return bins;
}

@end
