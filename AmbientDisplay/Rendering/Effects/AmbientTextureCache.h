#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// The one place that resolves a package-supplied relative texture path
// (e.g. "textures/raindrop.png") into an actual image. Every effect
// renderer that supports a texture parameter goes through this rather
// than touching NSFileManager/UIImage directly, so the containment and
// size rules live in exactly one place:
//   - rejects paths containing ".." or an absolute path - resolution is
//     always strictly relative to, and contained within, themeDirectoryURL
//   - rejects files above a size cap before decode (avoids a small file
//     decoding into a huge in-memory image)
//   - rejects decoded dimensions above a size cap
//   - restricts to a fixed set of decodable formats (PNG/JPEG)
// Any violation returns nil (logged), never throws - same posture as
// the rest of the package-parsing pipeline.
@interface AmbientTextureCache : NSObject

- (instancetype)initWithThemeDirectoryURL:(NSURL *)themeDirectoryURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Decoded images are cached by resolved path for the lifetime of this
// cache instance (i.e. for the lifetime of the theme it was built for),
// so multiple effects/primitives reusing one texture only pay to decode
// it once.
- (nullable UIImage *)imageNamed:(NSString *)relativePath;

@end

NS_ASSUME_NONNULL_END
