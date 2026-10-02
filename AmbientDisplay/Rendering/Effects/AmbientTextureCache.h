#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AmbientTextureCache : NSObject

- (instancetype)initWithThemeDirectoryURL:(NSURL *)themeDirectoryURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (nullable UIImage *)imageNamed:(NSString *)relativePath;

@end

NS_ASSUME_NONNULL_END
