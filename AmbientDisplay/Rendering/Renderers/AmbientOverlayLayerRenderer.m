#import "AmbientOverlayLayerRenderer.h"
#import "PackageManager.h"
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface AmbientOverlayLayerRenderer ()
@property (nonatomic, strong) UIView *stubView;
@end

@implementation AmbientOverlayLayerRenderer

+ (nullable instancetype)rendererWithThemeLayer:(AmbientThemeLayer *)themeLayer
                                          context:(AmbientThemeRenderContext *)context {
    if (![themeLayer.kind isEqualToString:@"overlay"]) {
        return nil;
    }

    AmbientOverlayLayerRenderer *renderer = [[AmbientOverlayLayerRenderer alloc] init];
    renderer.stubView = [[UIView alloc] init];
    renderer.stubView.backgroundColor = [UIColor clearColor];
    return renderer;
}

- (UIView *)view {
    return self.stubView;
}

- (void)start {
    // TODO: instantiate the locked-down WKWebView and load the
    // package-supplied html/css described in the header.
}

- (void)stop {
    // TODO: tear down the WKWebView.
}

@end

NS_ASSUME_NONNULL_END
