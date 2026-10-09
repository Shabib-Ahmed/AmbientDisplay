#import <Foundation/Foundation.h>

@class PackageManager;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const AmbientPackageImporterErrorDomain;

/// summary: human-readable result, e.g. Theme "Sample Scene".
/// replacedExisting: YES if a package with the same packageId was already installed.
typedef void (^AmbientPackageImportCompletion)(NSString * _Nullable summary,
                                               BOOL replacedExisting,
                                               NSError * _Nullable error);

/// Imports a package .zip into Documents/AmbientDisplay/Packages/.
///
/// Extraction and validation run on a background queue in a staging directory;
/// nothing touches Packages/ unless the package validates. Validation reuses
/// PackageManager's own parser (on a throwaway instance), so "imports
/// successfully" means "will actually load". The final install, the
/// PackageManager reload, and the completion all happen on the main queue.
///
/// The zip may have manifest.json at its root, or inside a single top-level
/// folder (what Finder's "Compress" produces).
@interface AmbientPackageImporter : NSObject

+ (void)importZipAtURL:(NSURL *)zipURL
        packageManager:(PackageManager *)packageManager
            completion:(AmbientPackageImportCompletion)completion;

@end

NS_ASSUME_NONNULL_END
