#import "AmbientTextureCache.h"

NS_ASSUME_NONNULL_BEGIN

// Reject any file above this size before even attempting to decode it -
static const unsigned long long kMaxFileSizeBytes = 10 * 1024 * 1024; // 10 MB

// Reject anything that decodes larger than this on either axis.
static const CGFloat kMaxDecodedDimension = 4096;

@interface AmbientTextureCache ()

@property (nonatomic, copy) NSURL *themeDirectoryURL;
@property (nonatomic, copy) NSURL *resolvedThemeDirectoryURL; // standardized, for containment checks
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *decodedImagesByPath;

@end

@implementation AmbientTextureCache

- (instancetype)initWithThemeDirectoryURL:(NSURL *)themeDirectoryURL {
    self = [super init];
    if (self) {
        _themeDirectoryURL = [themeDirectoryURL copy];
        _resolvedThemeDirectoryURL = [themeDirectoryURL URLByStandardizingPath];
        _decodedImagesByPath = [NSMutableDictionary dictionary];
    }
    return self;
}

- (nullable UIImage *)imageNamed:(NSString *)relativePath {
    if (![relativePath isKindOfClass:[NSString class]] || relativePath.length == 0) {
        NSLog(@"[AmbientTextureCache] empty/invalid relative path");
        return nil;
    }

    UIImage *cached = self.decodedImagesByPath[relativePath];
    if (cached) {
        return cached;
    }

    NSURL *resolvedURL = [self resolvedURLForRelativePath:relativePath];
    if (!resolvedURL) {
        return nil;
    }

    NSString *extension = resolvedURL.pathExtension.lowercaseString;
    if (![extension isEqualToString:@"png"] &&
        ![extension isEqualToString:@"jpg"] &&
        ![extension isEqualToString:@"jpeg"]) {
        NSLog(@"[AmbientTextureCache] unsupported texture format '%@' for %@", extension, relativePath);
        return nil;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *resolvedPath = resolvedURL.path;

    NSError *attrError = nil;
    NSDictionary<NSFileAttributeKey, id> *attrs = [fm attributesOfItemAtPath:resolvedPath error:&attrError];
    if (!attrs) {
        NSLog(@"[AmbientTextureCache] texture not found on disk: %@ (%@)", relativePath, attrError);
        return nil;
    }

    unsigned long long fileSize = attrs.fileSize;
    if (fileSize == 0 || fileSize > kMaxFileSizeBytes) {
        NSLog(@"[AmbientTextureCache] texture %@ rejected: size %llu bytes exceeds cap", relativePath, fileSize);
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfFile:resolvedPath];
    if (!data) {
        NSLog(@"[AmbientTextureCache] failed to read texture data: %@", relativePath);
        return nil;
    }

    UIImage *image = [UIImage imageWithData:data];
    if (!image) {
        NSLog(@"[AmbientTextureCache] failed to decode texture: %@", relativePath);
        return nil;
    }

    CGFloat pixelWidth = image.size.width * image.scale;
    CGFloat pixelHeight = image.size.height * image.scale;
    if (pixelWidth > kMaxDecodedDimension || pixelHeight > kMaxDecodedDimension) {
        NSLog(@"[AmbientTextureCache] texture %@ rejected: decoded dimensions %.0fx%.0f exceed cap",
              relativePath, pixelWidth, pixelHeight);
        return nil;
    }

    self.decodedImagesByPath[relativePath] = image;
    return image;
}

#pragma mark - Path resolution / containment

- (nullable NSURL *)resolvedURLForRelativePath:(NSString *)relativePath {
    if ([relativePath hasPrefix:@"/"]) {
        NSLog(@"[AmbientTextureCache] rejected absolute path: %@", relativePath);
        return nil;
    }

    NSArray<NSString *> *components = [relativePath componentsSeparatedByString:@"/"];
    if ([components containsObject:@".."]) {
        NSLog(@"[AmbientTextureCache] rejected path with '..': %@", relativePath);
        return nil;
    }

    NSURL *candidate = [self.themeDirectoryURL URLByAppendingPathComponent:relativePath];
    NSURL *resolvedCandidate = [candidate URLByStandardizingPath];

    NSString *resolvedThemeDirPath = self.resolvedThemeDirectoryURL.path;
    if (![resolvedThemeDirPath hasSuffix:@"/"]) {
        resolvedThemeDirPath = [resolvedThemeDirPath stringByAppendingString:@"/"];
    }

    if (![resolvedCandidate.path hasPrefix:resolvedThemeDirPath]) {
        NSLog(@"[AmbientTextureCache] resolved path escapes theme directory: %@", relativePath);
        return nil;
    }

    return resolvedCandidate;
}

@end

NS_ASSUME_NONNULL_END
