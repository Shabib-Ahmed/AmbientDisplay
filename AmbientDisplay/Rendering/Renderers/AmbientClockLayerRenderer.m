#import "AmbientClockLayerRenderer.h"
#import "PackageManager.h"

NS_ASSUME_NONNULL_BEGIN

static NSString * const kDefaultFormat = @"h:mm";
static NSString * const kDefaultFontName = @"HelveticaNeue-Thin";
static const CGFloat kDefaultFontSize = 72.0;
static const CGFloat kDefaultPositionX = 0.5;
static const CGFloat kDefaultPositionY = 0.5;

// Simple container view that keeps its label centered at a normalized
// (0-1, 0-1) point within its own bounds, regardless of how the
// compositor resizes this renderer's view. Owning this as a small view
// subclass (rather than doing the math in the renderer) means it stays
// correct across rotation/resize without the renderer needing to observe
// bounds changes itself.
@interface AmbientClockContainerView : UIView
@property (nonatomic, strong, readonly) UILabel *label;
@property (nonatomic, assign) CGPoint normalizedPosition;
@end

@implementation AmbientClockContainerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _normalizedPosition = CGPointMake(kDefaultPositionX, kDefaultPositionY);
        _label = [[UILabel alloc] init];
        _label.backgroundColor = [UIColor clearColor];
        _label.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_label];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self.label sizeToFit];
    self.label.center = CGPointMake(self.bounds.size.width * self.normalizedPosition.x,
                                     self.bounds.size.height * self.normalizedPosition.y);
}

- (void)setNormalizedPosition:(CGPoint)normalizedPosition {
    _normalizedPosition = normalizedPosition;
    [self setNeedsLayout];
}

@end

// Best-effort "#RRGGBB" / "#RRGGBBAA" parser. Anything that doesn't match
// falls back to the caller-supplied default rather than failing the
// whole renderer over a cosmetic parameter - same permissive posture the
// rest of this header calls for ("all optional, with sensible defaults").
static UIColor *AmbientColorFromHexString(id hexValue, UIColor *fallback) {
    if (![hexValue isKindOfClass:[NSString class]]) {
        return fallback;
    }
    NSString *hex = [(NSString *)hexValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([hex hasPrefix:@"#"]) {
        hex = [hex substringFromIndex:1];
    }
    if (hex.length != 6 && hex.length != 8) {
        return fallback;
    }
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    unsigned int value = 0;
    if (![scanner scanHexInt:&value] || !scanner.isAtEnd) {
        return fallback;
    }
    CGFloat a = 1.0, r, g, b;
    if (hex.length == 8) {
        a = ((value >> 24) & 0xFF) / 255.0;
        r = ((value >> 16) & 0xFF) / 255.0;
        g = ((value >> 8) & 0xFF) / 255.0;
        b = (value & 0xFF) / 255.0;
    } else {
        r = ((value >> 16) & 0xFF) / 255.0;
        g = ((value >> 8) & 0xFF) / 255.0;
        b = (value & 0xFF) / 255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

@interface AmbientClockLayerRenderer ()

@property (nonatomic, strong) AmbientClockContainerView *containerView;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong, nullable) NSTimer *timer;

@end

@implementation AmbientClockLayerRenderer

+ (nullable instancetype)rendererWithThemeLayer:(AmbientThemeLayer *)themeLayer
                                         context:(AmbientThemeRenderContext *)context {
    if (![themeLayer.kind isEqualToString:@"clock"]) {
        return nil;
    }

    NSDictionary<NSString *, id> *params = themeLayer.parameters ?: @{};

    NSString *format = kDefaultFormat;
    if ([params[@"format"] isKindOfClass:[NSString class]] && [(NSString *)params[@"format"] length] > 0) {
        format = params[@"format"];
    }
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    // A malformed pattern still yields a usable (if ugly) formatter -
    // there's no reliable way to pre-validate an arbitrary date format
    // string, so a bad "format" degrades the display rather than
    // dropping the whole layer, consistent with every other parameter
    // here.
    dateFormatter.dateFormat = format;

    NSString *fontName = kDefaultFontName;
    if ([params[@"font"] isKindOfClass:[NSString class]] && [(NSString *)params[@"font"] length] > 0) {
        fontName = params[@"font"];
    }

    CGFloat fontSize = kDefaultFontSize;
    if ([params[@"size"] isKindOfClass:[NSNumber class]]) {
        CGFloat candidate = [(NSNumber *)params[@"size"] doubleValue];
        if (candidate > 0) {
            fontSize = candidate;
        }
    }

    UIFont *font = [UIFont fontWithName:fontName size:fontSize];
    if (font == nil) {
        // Unrecognized font name - fall back to system rather than
        // failing the renderer over a cosmetic parameter.
        font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightThin];
    }

    UIColor *color = AmbientColorFromHexString(params[@"color"], [UIColor whiteColor]);

    CGPoint position = CGPointMake(kDefaultPositionX, kDefaultPositionY);
    if ([params[@"position"] isKindOfClass:[NSDictionary class]]) {
        NSDictionary *positionDict = params[@"position"];
        if ([positionDict[@"x"] isKindOfClass:[NSNumber class]]) {
            position.x = MAX(0.0, MIN(1.0, [(NSNumber *)positionDict[@"x"] doubleValue]));
        }
        if ([positionDict[@"y"] isKindOfClass:[NSNumber class]]) {
            position.y = MAX(0.0, MIN(1.0, [(NSNumber *)positionDict[@"y"] doubleValue]));
        }
    }

    AmbientClockLayerRenderer *renderer = [[AmbientClockLayerRenderer alloc] init];
    renderer.dateFormatter = dateFormatter;
    renderer.containerView = [[AmbientClockContainerView alloc] initWithFrame:CGRectZero];
    renderer.containerView.label.font = font;
    renderer.containerView.label.textColor = color;
    renderer.containerView.normalizedPosition = position;

    return renderer;
}

- (UIView *)view {
    return self.containerView;
}

- (void)start {
    [self tick];
    [self.timer invalidate];
    // Ticks once a second; not phase-aligned to the system clock's
    // second boundary, so the displayed value can lag by up to ~1s.
    // Fine for an ambient/minute-or-second-granularity display - not
    // worth the run-loop tolerance tricks a stopwatch-grade timer would
    // need.
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                    target:self
                                                  selector:@selector(tick)
                                                  userInfo:nil
                                                   repeats:YES];
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)tick {
    self.containerView.label.text = [self.dateFormatter stringFromDate:[NSDate date]];
    [self.containerView setNeedsLayout];
}

- (void)dealloc {
    [_timer invalidate];
}

@end

NS_ASSUME_NONNULL_END
