#import <Foundation/Foundation.h>
#import "AmbientThemeLayerRenderer.h"

NS_ASSUME_NONNULL_BEGIN

// Renders "kind": "clock" layers. Deliberately native (a plain text
// layer on a native timer) rather than DOM content in the overlay
// WKWebView

@interface AmbientClockLayerRenderer : NSObject <AmbientThemeLayerRenderer>

@end

NS_ASSUME_NONNULL_END
