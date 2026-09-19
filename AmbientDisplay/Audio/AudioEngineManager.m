#import "AudioEngineManager.h"
#import "PackageManager.h"
#import <Accelerate/Accelerate.h>

static NSUInteger const kSpectrumBinCount = 32;
static NSUInteger const kFFTFrameSize = 4096;
static NSUInteger const kFFTLog2n = 12;


static double const kMinBandHz = 40.0;
static double const kMaxBandHz = 16000.0;

static float const kNoiseFloor = 0.004f;
static double const kPeakHalfLifeSeconds = 3.0;

static float const kTiltExponent = 0.3f;

// Final shaping: <1 lifts quiet bars so small movements stay visible.
static float const kOutputGamma = 0.75f;

@interface AudioEngineManager ()

@property (nonatomic, strong) PackageManager *packageManager;

@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *playerNode;

@property (nonatomic, copy) NSArray<NSURL *> *queueURLs;
@property (nonatomic, assign) NSUInteger queueIndex;
@property (nonatomic, copy, nullable) NSString *loadedPlaylistId;

@property (nonatomic, assign) BOOL playing;

@property (atomic, copy, readwrite, nullable) NSArray<NSNumber *> *latestSpectrumBins;

// Auto-gain state. Read and written only on the tap thread.
@property (nonatomic, assign) float smoothedPeak;

// Main-thread only.
@property (nonatomic, assign) BOOL resumeAfterInterruption;
@property (nonatomic, assign) NSUInteger scheduleGeneration;

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

        // FFT first: the tap is installed (and can fire) inside
        // setUpAudioEngine, and it needs the setup and window to exist.
        [self setUpFFT];
        [self setUpAudioEngine];
        [self registerForAudioNotifications];

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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
    [self ensureEngineRunning];
    if (!self.engine.isRunning) return; // -[AVAudioPlayerNode play] raises if the engine is stopped
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

    // Bump before stopping: stop can fire the previous file's completion
    // handler, and that stale callback must not advance the queue.
    self.scheduleGeneration += 1;
    NSUInteger generation = self.scheduleGeneration;

    [self.playerNode stop];

    __weak typeof(self) weakSelf = self;
    [self.playerNode scheduleFile:file
                            atTime:nil
                 completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack
                 completionHandler:^(AVAudioPlayerNodeCompletionCallbackType callbackType) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleTrackFinishedForGeneration:generation];
        });
    }];

    [self ensureEngineRunning];
    if (self.engine.isRunning) {
        [self.playerNode play];
        self.playing = YES;
    }

    NSLog(@"[AudioEngineManager] now playing (%lu/%lu): %@",
          (unsigned long)self.queueIndex + 1, (unsigned long)self.queueURLs.count, url.lastPathComponent);

    [self notifyTrackChangeForURL:url];
    [self extractID3TagsForURL:url];
}

- (void)handleTrackFinishedForGeneration:(NSUInteger)generation {
    if (generation != self.scheduleGeneration) return; // stale: a newer schedule superseded this one
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
    if (!self.fftSetup || !self.hannWindow) return;
    if (buffer.frameLength == 0 || buffer.floatChannelData == NULL) return;

    double sampleRate = buffer.format.sampleRate;
    if (sampleRate <= 0.0) return;

    float *samples = buffer.floatChannelData[0];
    NSUInteger n = kFFTFrameSize;

    // The tap's bufferSize is only a hint. If a short buffer arrives, zero-pad
    // rather than dropping it (dropping would freeze the visualizer).
    NSUInteger available = MIN((NSUInteger)buffer.frameLength, n);

    float windowed[kFFTFrameSize];
    if (available < n) {
        memset(windowed, 0, sizeof(windowed));
    }
    vDSP_vmul(samples, 1, self.hannWindow, 1, windowed, 1, available);

    float realp[kFFTFrameSize / 2];
    float imagp[kFFTFrameSize / 2];
    DSPSplitComplex splitComplex = { .realp = realp, .imagp = imagp };

    vDSP_ctoz((DSPComplex *)windowed, 2, &splitComplex, 1, n / 2);
    vDSP_fft_zrip(self.fftSetup, &splitComplex, 1, kFFTLog2n, FFT_FORWARD);

    float power[kFFTFrameSize / 2];
    vDSP_zvmags(&splitComplex, 1, power, 1, n / 2);

    self.latestSpectrumBins = [self spectrumBinsFromPower:power
                                                     count:n / 2
                                                sampleRate:sampleRate
                                            bufferDuration:(double)available / sampleRate];
}


- (NSArray<NSNumber *> *)spectrumBinsFromPower:(const float *)power
                                          count:(NSUInteger)count
                                     sampleRate:(double)sampleRate
                                 bufferDuration:(double)duration {
    double binWidth = sampleRate / (double)kFFTFrameSize; // Hz per FFT bin
    double maxHz = MIN(kMaxBandHz, sampleRate * 0.5 * 0.98);
    double logMin = log2(kMinBandHz);
    double logMax = log2(maxHz);
    float scale = 1.0f / (float)kFFTFrameSize; // rough amplitude normalization

    NSInteger lastIndex = (NSInteger)count - 1;
    float rawBins[kSpectrumBinCount];
    float peak = 0.f;

    for (NSUInteger b = 0; b < kSpectrumBinCount; b++) {
        double f0 = pow(2.0, logMin + (logMax - logMin) * ((double)b / kSpectrumBinCount));
        double f1 = pow(2.0, logMin + (logMax - logMin) * ((double)(b + 1) / kSpectrumBinCount));
        double centerHz = sqrt(f0 * f1);
        double p0 = f0 / binWidth; // band edges as fractional FFT-bin positions
        double p1 = f1 / binWidth;

        float amplitude;
        if (p1 - p0 < 1.0) {
            // Band is narrower than one FFT bin (the low end): interpolate the
            // spectrum at the band's center instead of repeating one bin, so
            // neighboring bars don't come out identical.
            double pc = centerHz / binWidth;
            NSInteger i0 = MIN(MAX((NSInteger)floor(pc), 1), lastIndex - 1);
            float frac = (float)MIN(MAX(pc - (double)i0, 0.0), 1.0);
            float a0 = sqrtf(power[i0]);
            float a1 = sqrtf(power[i0 + 1]);
            amplitude = a0 + (a1 - a0) * frac;
        } else {
            // Band spans one or more whole bins: RMS across them.
            NSInteger first = MIN(MAX((NSInteger)ceil(p0), 1), lastIndex);
            NSInteger last = MIN(MAX((NSInteger)floor(p1), first), lastIndex);
            float sum = 0.f;
            for (NSInteger i = first; i <= last; i++) {
                sum += power[i];
            }
            amplitude = sqrtf(sum / (float)(last - first + 1));
        }

        amplitude *= scale;
        if (kTiltExponent > 0.f) {
            amplitude *= powf((float)(centerHz / 500.0), kTiltExponent);
        }

        rawBins[b] = amplitude;
        if (amplitude > peak) peak = amplitude;
    }

    // Auto-gain: jump up to a new peak instantly, relax down over seconds.
    float decay = (float)pow(0.5, duration / kPeakHalfLifeSeconds);
    self.smoothedPeak = MAX(peak, self.smoothedPeak * decay);
    float reference = MAX(self.smoothedPeak, kNoiseFloor);

#if DEBUG
    // Tuning aid for kNoiseFloor: ~1 line per second. Remove when settled.
    static NSUInteger logCounter = 0;
    if ((++logCounter % 10) == 0) {
        NSLog(@"[Spectrum] framePeak=%.5f smoothedPeak=%.5f floor=%.5f", peak, self.smoothedPeak, kNoiseFloor);
    }
#endif

    NSMutableArray<NSNumber *> *bins = [NSMutableArray arrayWithCapacity:kSpectrumBinCount];
    for (NSUInteger b = 0; b < kSpectrumBinCount; b++) {
        float normalized = MIN(rawBins[b] / reference, 1.f);
        [bins addObject:@(powf(normalized, kOutputGamma))];
    }
    return bins;
}

#pragma mark - Engine recovery (interruptions / route changes)

- (void)registerForAudioNotifications {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(handleAudioSessionInterruption:)
                   name:AVAudioSessionInterruptionNotification
                 object:[AVAudioSession sharedInstance]];
    [center addObserver:self
               selector:@selector(handleEngineConfigurationChange:)
                   name:AVAudioEngineConfigurationChangeNotification
                 object:self.engine];
}

- (void)ensureEngineRunning {
    if (self.engine.isRunning) return;
    NSError *error = nil;
    if (![self.engine startAndReturnError:&error]) {
        NSLog(@"[AudioEngineManager] failed to (re)start AVAudioEngine: %@", error);
    }
}

// Phone call, Siri, another app taking the session. The system has already
// stopped the engine by the time "began" arrives, so we only record intent.
- (void)handleAudioSessionInterruption:(NSNotification *)notification {
    NSUInteger type = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    NSUInteger options = [notification.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (type == AVAudioSessionInterruptionTypeBegan) {
            self.resumeAfterInterruption = self.playing;
            self.playing = NO;
            return;
        }

        // Ended
        BOOL shouldResume = (options & AVAudioSessionInterruptionOptionShouldResume) != 0;
        BOOL wasPlaying = self.resumeAfterInterruption;
        self.resumeAfterInterruption = NO;
        if (!shouldResume) return;

        NSError *error = nil;
        if (![[AVAudioSession sharedInstance] setActive:YES error:&error]) {
            NSLog(@"[AudioEngineManager] failed to reactivate audio session: %@", error);
        }
        [self ensureEngineRunning];
        if (wasPlaying) {
            [self play];
        }
    });
}

// Output route or hardware format changed (headphones, AirPlay, sample rate).
// The engine has stopped and the tap's format may be stale, so rebuild the
// graph around the new format. If we were playing, restart the current track
// (its scheduled audio does not survive the reconfiguration).
- (void)handleEngineConfigurationChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.engine.isRunning) return;

        BOOL wasPlaying = self.playing;
        [self tearDownTap];

        AVAudioFormat *format = [self.engine.mainMixerNode outputFormatForBus:0];
        [self.engine connect:self.playerNode to:self.engine.mainMixerNode format:format];
        [self installTap];
        [self ensureEngineRunning];

        if (wasPlaying) {
            [self scheduleAndPlayCurrentIndex];
        }
    });
}

@end
