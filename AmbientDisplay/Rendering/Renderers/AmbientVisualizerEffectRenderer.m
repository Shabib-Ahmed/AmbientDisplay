#import "AmbientVisualizerEffectRenderer.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "PackageManager.h"
#import "AmbientAudioDataSource.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AmbientVisualizerStyle) {
    AmbientVisualizerStyleBars = 0,
    AmbientVisualizerStyleWaveform,
};

static const NSUInteger kDefaultBarCount = 32;
static const NSUInteger kMinBarCount = 4;
static const NSUInteger kMaxBarCount = 128;
static const CGFloat kAttackFactor = 0.6;       // how fast levels rise toward a louder target
static const CGFloat kDefaultSmoothing = 0.85;  // higher = slower fall-off
static const CGFloat kMinBarHeight = 2.0;       // keeps an idle visualizer faintly visible

#pragma mark - Drawing view

@interface AmbientVisualizerView : UIView
@property (nonatomic, assign) AmbientVisualizerStyle style;
@property (nonatomic, assign) CGFloat gapRatio;      // fraction of each bar slot left empty (bars only)
@property (nonatomic, assign) CGFloat cornerRadius;  // bars only
- (void)renderLevels:(const CGFloat *)levels count:(NSUInteger)count;
@end

@implementation AmbientVisualizerView

+ (Class)layerClass {
    return [CAShapeLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.opaque = NO;
        self.gapRatio = 0.35;
        self.cornerRadius = 2.0;
        ((CAShapeLayer *)self.layer).fillColor = [UIColor whiteColor].CGColor;
    }
    return self;
}

- (void)setTintColor:(nullable UIColor *)tintColor {
    [super setTintColor:tintColor];
}

- (void)setFillColor:(UIColor *)color {
    ((CAShapeLayer *)self.layer).fillColor = color.CGColor;
}

- (void)renderLevels:(const CGFloat *)levels count:(NSUInteger)count {
    CGRect bounds = self.bounds;
    if (count == 0 || CGRectIsEmpty(bounds)) {
        ((CAShapeLayer *)self.layer).path = NULL;
        return;
    }

    UIBezierPath *path = (self.style == AmbientVisualizerStyleWaveform)
        ? [self waveformPathForLevels:levels count:count bounds:bounds]
        : [self barsPathForLevels:levels count:count bounds:bounds];
    ((CAShapeLayer *)self.layer).path = path.CGPath;
}

- (UIBezierPath *)barsPathForLevels:(const CGFloat *)levels count:(NSUInteger)count bounds:(CGRect)bounds {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat slot = bounds.size.width / (CGFloat)count;
    CGFloat barWidth = MAX(1.0, slot * (1.0 - self.gapRatio));
    CGFloat inset = (slot - barWidth) * 0.5;

    for (NSUInteger i = 0; i < count; i++) {
        CGFloat h = MAX(kMinBarHeight, levels[i] * bounds.size.height);
        h = MIN(h, bounds.size.height);
        CGRect r = CGRectMake(bounds.origin.x + slot * i + inset,
                              CGRectGetMaxY(bounds) - h,
                              barWidth,
                              h);
        CGFloat radius = MIN(self.cornerRadius, barWidth * 0.5);
        [path appendPath:[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:radius]];
    }
    return path;
}


- (UIBezierPath *)waveformPathForLevels:(const CGFloat *)levels count:(NSUInteger)count bounds:(CGRect)bounds {
    UIBezierPath *path = [UIBezierPath bezierPath];
    if (count < 2) {
        return path;
    }

    CGFloat midY = CGRectGetMidY(bounds);
    CGFloat halfHeight = bounds.size.height * 0.5;
    CGFloat step = bounds.size.width / (CGFloat)(count - 1);

    CGPoint top[count];
    CGPoint bottom[count];
    for (NSUInteger i = 0; i < count; i++) {
        CGFloat amp = MAX(kMinBarHeight * 0.5, levels[i] * halfHeight);
        amp = MIN(amp, halfHeight);
        CGFloat x = bounds.origin.x + step * i;
        top[i] = CGPointMake(x, midY - amp);
        bottom[i] = CGPointMake(x, midY + amp);
    }

    [path moveToPoint:top[0]];
    for (NSUInteger i = 1; i < count; i++) {
        CGPoint mid = CGPointMake((top[i - 1].x + top[i].x) * 0.5, (top[i - 1].y + top[i].y) * 0.5);
        [path addQuadCurveToPoint:mid controlPoint:top[i - 1]];
    }
    [path addLineToPoint:top[count - 1]];
    [path addLineToPoint:bottom[count - 1]];
    for (NSInteger i = (NSInteger)count - 1; i >= 1; i--) {
        CGPoint mid = CGPointMake((bottom[i].x + bottom[i - 1].x) * 0.5, (bottom[i].y + bottom[i - 1].y) * 0.5);
        [path addQuadCurveToPoint:mid controlPoint:bottom[i]];
    }
    [path addLineToPoint:bottom[0]];
    [path closePath];
    return path;
}

@end

#pragma mark - Container (places the drawing view at a normalized sub-rect)

@interface AmbientVisualizerContainerView : UIView
@property (nonatomic, strong) AmbientVisualizerView *visualizerView;
@property (nonatomic, assign) CGRect normalizedFrame; // x, y, width, height as 0...1 fractions
@end

@implementation AmbientVisualizerContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _normalizedFrame = CGRectMake(0, 0, 1, 1);
    }
    return self;
}

- (void)setVisualizerView:(AmbientVisualizerView *)visualizerView {
    [_visualizerView removeFromSuperview];
    _visualizerView = visualizerView;
    if (visualizerView) {
        [self addSubview:visualizerView];
        [self setNeedsLayout];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGRect n = self.normalizedFrame;
    self.visualizerView.frame = CGRectMake(b.origin.x + n.origin.x * b.size.width,
                                           b.origin.y + n.origin.y * b.size.height,
                                           n.size.width * b.size.width,
                                           n.size.height * b.size.height);
}

@end

#pragma mark - Display link target (avoids CADisplayLink retaining the renderer)

@interface AmbientVisualizerDisplayLinkTarget : NSObject
@property (nonatomic, weak, nullable) id owner;
@property (nonatomic, assign) SEL action;
- (void)tick:(CADisplayLink *)link;
@end

@implementation AmbientVisualizerDisplayLinkTarget
- (void)tick:(CADisplayLink *)link {
    id owner = self.owner;
    if (!owner) {
        [link invalidate];
        return;
    }
    IMP imp = [owner methodForSelector:self.action];
    void (*fn)(id, SEL, CADisplayLink *) = (void (*)(id, SEL, CADisplayLink *))imp;
    fn(owner, self.action, link);
}
@end

#pragma mark - Renderer

@interface AmbientVisualizerEffectRenderer ()
@property (nonatomic, strong) AmbientVisualizerView *visualizerView;
@property (nonatomic, strong) AmbientVisualizerContainerView *containerView;
@property (nonatomic, weak, nullable) id<AmbientAudioDataSource> audioDataSource;
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;

@property (nonatomic, assign) NSUInteger barCount;
@property (nonatomic, assign) CGFloat smoothing;
@property (nonatomic, assign) CGFloat sensitivity;
@property (nonatomic, strong) NSMutableData *levelData;  // CGFloat[barCount], smoothed 0...1
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

    NSDictionary *params = themeLayer.parameters;

    AmbientVisualizerEffectRenderer *renderer = [[AmbientVisualizerEffectRenderer alloc] init];
    renderer.audioDataSource = context.audioDataSource;

    // Parameters (all optional):
    //   style:       "bars" (default) | "waveform"
    //   color:       "#RRGGBB" or "#RRGGBBAA" (default white)
    //   barCount:    4...128 (default 32)
    //   smoothing:   0...1, higher falls slower (default 0.85)
    //   sensitivity: gain multiplier applied to bins (default 1.0)
    //   gap:         0...0.9 fraction of each bar slot left empty (default 0.35)
    //   cornerRadius: points, bars only (default 2)
    NSUInteger barCount = [self unsignedParam:params[@"barCount"] fallback:kDefaultBarCount];
    renderer.barCount = MIN(MAX(barCount, kMinBarCount), kMaxBarCount);
    renderer.smoothing = [self clampedFloat:params[@"smoothing"] fallback:kDefaultSmoothing min:0.0 max:0.99];
    renderer.sensitivity = [self clampedFloat:params[@"sensitivity"] fallback:1.0 min:0.0 max:10.0];
    renderer.levelData = [NSMutableData dataWithLength:renderer.barCount * sizeof(CGFloat)];

    AmbientVisualizerView *view = [[AmbientVisualizerView alloc] initWithFrame:CGRectZero];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    id styleValue = params[@"style"];
    if ([styleValue isKindOfClass:[NSString class]] &&
        [[(NSString *)styleValue lowercaseString] isEqualToString:@"waveform"]) {
        view.style = AmbientVisualizerStyleWaveform;
    } else {
        view.style = AmbientVisualizerStyleBars;
    }
    view.gapRatio = [self clampedFloat:params[@"gap"] fallback:0.35 min:0.0 max:0.9];
    view.cornerRadius = [self clampedFloat:params[@"cornerRadius"] fallback:2.0 min:0.0 max:50.0];
    [view setFillColor:[self colorFromHexString:params[@"color"]] ?: [UIColor whiteColor]];
    renderer.visualizerView = view;


    CGRect normalized = CGRectMake(0, 0, 1, 1);
    id frameValue = params[@"frame"];
    if ([frameValue isKindOfClass:[NSDictionary class]]) {
        NSDictionary *f = (NSDictionary *)frameValue;
        CGFloat x = [self clampedFloat:f[@"x"] fallback:0.0 min:0.0 max:1.0];
        CGFloat y = [self clampedFloat:f[@"y"] fallback:0.0 min:0.0 max:1.0];
        CGFloat w = [self clampedFloat:f[@"width"] fallback:1.0 min:0.0 max:1.0];
        CGFloat h = [self clampedFloat:f[@"height"] fallback:1.0 min:0.0 max:1.0];
        normalized = CGRectMake(x, y, MIN(w, 1.0 - x), MIN(h, 1.0 - y));
    }
    AmbientVisualizerContainerView *container = [[AmbientVisualizerContainerView alloc] initWithFrame:CGRectZero];
    container.normalizedFrame = normalized;
    container.visualizerView = view;
    renderer.containerView = container;

    return renderer;
}

- (void)dealloc {
    [_displayLink invalidate];
}

- (UIView *)view {
    return self.containerView;
}

- (void)start {
    if (self.displayLink) {
        return;
    }
    AmbientVisualizerDisplayLinkTarget *target = [[AmbientVisualizerDisplayLinkTarget alloc] init];
    target.owner = self;
    target.action = @selector(handleDisplayLink:);

    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
    link.preferredFramesPerSecond = 30;
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.displayLink = link;
}

- (void)stop {
    [self.displayLink invalidate];
    self.displayLink = nil;

    // Clear so a restart doesn't begin from stale levels.
    memset(self.levelData.mutableBytes, 0, self.levelData.length);
    [self.visualizerView renderLevels:self.levelData.bytes count:self.barCount];
}

#pragma mark - Frame update

- (void)handleDisplayLink:(CADisplayLink *)link {
    CGFloat *levels = (CGFloat *)self.levelData.mutableBytes;
    NSUInteger count = self.barCount;

    // Single atomic read per frame; nil until the first buffer arrives.
    NSArray<NSNumber *> *bins = self.audioDataSource.latestSpectrumBins;
    NSUInteger binCount = bins.count;

    CGFloat release = 1.0 - self.smoothing;

    for (NSUInteger i = 0; i < count; i++) {
        CGFloat target = 0.0;
        if (binCount > 0) {
            // Resample source bins into `count` groups by averaging.
            NSUInteger start = (i * binCount) / count;
            NSUInteger end = MAX(start + 1, ((i + 1) * binCount) / count);
            end = MIN(end, binCount);
            CGFloat sum = 0.0;
            for (NSUInteger j = start; j < end; j++) {
                sum += [bins[j] doubleValue];
            }
            target = sum / (CGFloat)(end - start);
            target = MIN(MAX(target * self.sensitivity, 0.0), 1.0);
        }

        CGFloat prev = levels[i];
        CGFloat factor = (target > prev) ? kAttackFactor : release;
        levels[i] = prev + (target - prev) * factor;
    }

    [self.visualizerView renderLevels:levels count:count];
}

#pragma mark - Parameter parsing

+ (NSUInteger)unsignedParam:(nullable id)value fallback:(NSUInteger)fallback {
    if ([value isKindOfClass:[NSNumber class]]) {
        NSInteger v = [(NSNumber *)value integerValue];
        return v > 0 ? (NSUInteger)v : fallback;
    }
    return fallback;
}

+ (CGFloat)clampedFloat:(nullable id)value fallback:(CGFloat)fallback min:(CGFloat)min max:(CGFloat)max {
    CGFloat v = fallback;
    if ([value isKindOfClass:[NSNumber class]]) {
        v = [(NSNumber *)value doubleValue];
    }
    return MIN(MAX(v, min), max);
}

+ (nullable UIColor *)colorFromHexString:(nullable id)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *hex = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([hex hasPrefix:@"#"]) {
        hex = [hex substringFromIndex:1];
    }
    if (hex.length != 6 && hex.length != 8) {
        return nil;
    }
    unsigned long long raw = 0;
    if (![[NSScanner scannerWithString:hex] scanHexLongLong:&raw]) {
        return nil;
    }
    CGFloat r, g, b, a = 1.0;
    if (hex.length == 6) {
        r = ((raw >> 16) & 0xFF) / 255.0;
        g = ((raw >> 8) & 0xFF) / 255.0;
        b = (raw & 0xFF) / 255.0;
    } else {
        r = ((raw >> 24) & 0xFF) / 255.0;
        g = ((raw >> 16) & 0xFF) / 255.0;
        b = ((raw >> 8) & 0xFF) / 255.0;
        a = (raw & 0xFF) / 255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

@end

NS_ASSUME_NONNULL_END
