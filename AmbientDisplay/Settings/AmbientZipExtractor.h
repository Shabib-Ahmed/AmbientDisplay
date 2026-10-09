#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const AmbientZipExtractorErrorDomain;

/// Minimal, dependency-free zip extractor built on libcompression.
///
/// Supports stored (0) and deflate (8) entries. Does not support zip64,
/// encryption, or symlinks (all rejected with an error). Entry paths are
/// containment-checked (no "..", no absolute paths), and total extracted size
/// and entry count are capped, so a hostile archive can't write outside
/// `directoryURL` or fill the disk unbounded.
@interface AmbientZipExtractor : NSObject

+ (BOOL)extractZipAtURL:(NSURL *)zipURL
         toDirectoryURL:(NSURL *)directoryURL
                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
