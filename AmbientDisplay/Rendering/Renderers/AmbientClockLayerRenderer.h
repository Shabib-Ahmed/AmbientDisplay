#import <Foundation/Foundation.h>
#import "AmbientThemeLayerRenderer.h"

NS_ASSUME_NONNULL_BEGIN

// Renders "kind": "clock" layers. Deliberately native (a plain text
// layer on a native timer) rather than DOM content in the overlay
// WKWebView, for two reasons: it needs to keep ticking with JavaScript
// disabled in that webview, and being its own layer is what lets a
// package place effects both behind and in front of the clock by simply
// reordering entries in "layers".
//
// Recognized (all optional, with sensible defaults if omitted):
//   format   - e.g. "h:mm"
//   font     - a font name resolvable via UIFont
//   size     - point size
//   color    - hex string
//   position - {"x": 0-1, "y": 0-1} normalized to the layer's bounds
@interface AmbientClockLayerRenderer : NSObject <AmbientThemeLayerRenderer>

@end

NS_ASSUME_NONNULL_END
