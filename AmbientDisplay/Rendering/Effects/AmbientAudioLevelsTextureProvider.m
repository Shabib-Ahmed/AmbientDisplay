#import "AmbientAudioLevelsTextureProvider.h"

NS_ASSUME_NONNULL_BEGIN

static const CGFloat kDefaultAttackFactor = 0.6;   // ported from old AmbientVisualizerEffectRenderer
static const CGFloat kDefaultSmoothing = 0.85;     // ditto
static const CGFloat kDefaultSensitivity = 1.0;
static const CGFloat kMaxSensitivity = 10.0;

@interface AmbientAudioLevelsTextureProvider ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, assign) NSUInteger canonicalWidth;
@property (nonatomic, strong, nullable) id<MTLTexture> texture;
@property (nonatomic, strong) NSMutableData *smoothedLevels; // float[canonicalWidth]
@end

@implementation AmbientAudioLevelsTextureProvider

- (instancetype)initWithDevice:(id<MTLDevice>)device canonicalWidth:(NSUInteger)canonicalWidth {
    if ((self = [super init])) {
        _device = device;
        _canonicalWidth = canonicalWidth;
        _smoothing = kDefaultSmoothing;
        _sensitivity = kDefaultSensitivity;
        _smoothedLevels = [NSMutableData dataWithLength:canonicalWidth * sizeof(float)];

        MTLTextureDescriptor *descriptor =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR32Float
                                                                 width:canonicalWidth
                                                                height:1
                                                             mipmapped:NO];
        descriptor.usage = MTLTextureUsageShaderRead;
        descriptor.storageMode = MTLStorageModeShared;
        _texture = [device newTextureWithDescriptor:descriptor];
        if (!_texture) {
            NSLog(@"[AmbientAudioLevelsTextureProvider] failed to allocate %lu-wide levels texture",
                  (unsigned long)canonicalWidth);
        }
    }
    return self;
}

- (void)setSensitivity:(CGFloat)sensitivity {
    _sensitivity = MAX(0.0, MIN(kMaxSensitivity, sensitivity));
}

- (void)tick {
    if (!self.texture) {
        return;
    }

    NSArray<NSNumber *> *sourceBins = self.audioDataSource.latestSpectrumBins;
    NSUInteger sourceCount = sourceBins.count;
    NSUInteger width = self.canonicalWidth;
    float *smoothed = (float *)self.smoothedLevels.mutableBytes;

    for (NSUInteger i = 0; i < width; i++) {
        float target = 0.0f;

        if (sourceCount > 0) {
            NSUInteger start = (NSUInteger)((i * sourceCount) / width);
            NSUInteger end = (NSUInteger)(((i + 1) * sourceCount) / width);
            if (end <= start) {
                end = start + 1;
            }
            if (end > sourceCount) {
                end = sourceCount;
            }
            if (start >= sourceCount) {
                start = sourceCount - 1;
            }

            float sum = 0.0f;
            NSUInteger count = 0;
            for (NSUInteger j = start; j < end; j++) {
                sum += sourceBins[j].floatValue;
                count++;
            }
            target = (count > 0) ? (sum / (float)count) : 0.0f;
        }

        target *= (float)self.sensitivity;
        target = MAX(0.0f, MIN(1.0f, target));

        float previous = smoothed[i];
        float blendFactor = (target > previous)
            ? (float)kDefaultAttackFactor            // fast rise
            : (float)(1.0 - self.smoothing);         // slow fall
        smoothed[i] = previous + (target - previous) * blendFactor;
    }

    [self.texture replaceRegion:MTLRegionMake2D(0, 0, width, 1)
                     mipmapLevel:0
                       withBytes:smoothed
                     bytesPerRow:width * sizeof(float)];
}

@end

NS_ASSUME_NONNULL_END
