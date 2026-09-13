#import "AmbientOverlayLayerRenderer.h"
#import "PackageManager.h"
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

// STUB: kind filtering matches the factory's dispatch rules and the view
// is a real (empty) subview so it's safe to insert into the compositor
// stack today, but none of the WKWebView content/lockdown described in
// AmbientOverlayLayerRenderer.h is wired up yet. Specifically still
// TODO, all per the header:
//   - load themeLayer.parameters[@"html"]/[@"css"] from the theme
//     directory into a WKWebView
//   - disable JS (WKPreferences.javaScriptEnabled = NO)
//   - compiled WKContentRuleList blocking any non-same-origin resource
//     load
//   - allowingReadAccessToURL scoped to the theme's own directory
//   - navigation delegate cancelling any navigation past initial load
//   - dataDetectorTypes = none, allowsLinkPreview = NO
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
