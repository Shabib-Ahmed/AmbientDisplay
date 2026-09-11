#import <Foundation/Foundation.h>
#import "AmbientThemeLayerRenderer.h"

NS_ASSUME_NONNULL_BEGIN

// Renders "kind": "overlay" layers - package-supplied "html" and "css"
// loaded into a WKWebView. Because packages may eventually be
// third-party/shared, this webview is configured defensively:
//   - JavaScript disabled entirely (WKPreferences.javaScriptEnabled = NO)
//   - a compiled WKContentRuleList blocking any resource load that isn't
//     same-origin with the loaded file, so plain HTML/CSS can't
//     phone home via <img src>, CSS url(), <link>, etc. even without JS
//   - allowingReadAccessToURL scoped to just this theme's own directory,
//     not the wider Documents tree
//   - navigation delegate cancels any navigation past the initial load
//     (blocks anchor-tag navigation, which WKWebView still honors without
//     JavaScript)
//   - dataDetectorTypes = none, allowsLinkPreview = NO
// None of this is configurable per-package - it's the same lockdown for
// every overlay layer regardless of what the package's HTML contains.
@interface AmbientOverlayLayerRenderer : NSObject <AmbientThemeLayerRenderer>

@end

NS_ASSUME_NONNULL_END
