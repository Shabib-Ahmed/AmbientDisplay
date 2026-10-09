#import "AmbientPackageImporter.h"
#import "AmbientZipExtractor.h"
#import "PackageManager.h"

NSString * const AmbientPackageImporterErrorDomain = @"AmbientPackageImporterErrorDomain";

static NSError *ImportError(NSString *message) {
    return [NSError errorWithDomain:AmbientPackageImporterErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL IsSafePackageId(NSString *packageId) {
    // Used as a directory name, so keep it boring.
    return [packageId rangeOfString:@"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"
                            options:NSRegularExpressionSearch].location != NSNotFound;
}

@implementation AmbientPackageImporter

+ (void)importZipAtURL:(NSURL *)zipURL
        packageManager:(PackageManager *)packageManager
            completion:(AmbientPackageImportCompletion)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [[NSFileManager alloc] init];
        NSString *staging = [NSTemporaryDirectory()
            stringByAppendingPathComponent:[@"AmbientImport-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
        NSString *extracted = [staging stringByAppendingPathComponent:@"Extracted"];
        NSString *checkBase = [staging stringByAppendingPathComponent:@"Check"];
        NSString *checkPackages = [checkBase stringByAppendingPathComponent:@"Packages"];
        NSString *checkPackage = [checkPackages stringByAppendingPathComponent:@"pkg"];

        void (^fail)(NSString *) = ^(NSString *message) {
            [fm removeItemAtPath:staging error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, NO, ImportError(message));
            });
        };

        NSError *error = nil;
        if (![fm createDirectoryAtPath:checkPackages withIntermediateDirectories:YES attributes:nil error:&error]) {
            fail(error.localizedDescription ?: @"Couldn't create a working folder.");
            return;
        }

        if (![AmbientZipExtractor extractZipAtURL:zipURL
                                   toDirectoryURL:[NSURL fileURLWithPath:extracted isDirectory:YES]
                                            error:&error]) {
            fail(error.localizedDescription ?: @"Couldn't extract the zip.");
            return;
        }

        NSString *packageRoot = [self packageRootInExtractedDirectory:extracted fileManager:fm];
        if (!packageRoot) {
            fail(@"No manifest.json found. The zip must contain a package, with manifest.json at its top level.");
            return;
        }
        if (![fm moveItemAtPath:packageRoot toPath:checkPackage error:&error]) {
            fail(error.localizedDescription ?: @"Couldn't stage the package.");
            return;
        }

        // Validate with the real parser, on a throwaway manager.
        PackageManager *checker = [[PackageManager alloc] initWithBaseDirectoryPath:checkBase];
        [checker reloadInstalledPackages];
        AmbientTheme *theme = checker.installedThemes.firstObject;
        AmbientPlaylist *playlist = checker.installedPlaylists.firstObject;
        if (!theme && !playlist) {
            fail(@"That isn't a valid package. It needs a manifest.json with a valid theme (including its background video under Theme/) or playlist (with its tracks under Playlist/).");
            return;
        }

        NSString *packageId = theme ? theme.packageId : playlist.packageId;
        if (!IsSafePackageId(packageId)) {
            fail(@"The package's packageId may only contain letters, numbers, \".\", \"_\" and \"-\".");
            return;
        }
        NSString *summary = theme
            ? [NSString stringWithFormat:@"Theme “%@”", theme.displayName]
            : [NSString stringWithFormat:@"Playlist “%@”", playlist.packageId];

        // Install + reload on the main queue (reload fires KVO that drives UI).
        dispatch_async(dispatch_get_main_queue(), ^{
            NSFileManager *mainFM = [[NSFileManager alloc] init];
            NSString *packagesDir = [packageManager packagesDirPath];
            NSError *installError = nil;
            [mainFM createDirectoryAtPath:packagesDir withIntermediateDirectories:YES attributes:nil error:nil];

            NSString *existing = [self directoryInPackagesDir:packagesDir
                                                forPackageId:packageId
                                                 fileManager:mainFM];
            BOOL replaced = (existing != nil);
            BOOL ok = NO;

            if (existing) {
                ok = [mainFM replaceItemAtURL:[NSURL fileURLWithPath:existing isDirectory:YES]
                                withItemAtURL:[NSURL fileURLWithPath:checkPackage isDirectory:YES]
                               backupItemName:nil
                                      options:0
                             resultingItemURL:NULL
                                        error:&installError];
            } else {
                NSString *destination = [packagesDir stringByAppendingPathComponent:packageId];
                if ([mainFM fileExistsAtPath:destination]) {
                    installError = ImportError(@"A different item named like this package already exists in Packages.");
                } else {
                    ok = [mainFM moveItemAtPath:checkPackage toPath:destination error:&installError];
                }
            }

            [mainFM removeItemAtPath:staging error:nil];

            if (!ok) {
                completion(nil, NO, installError ?: ImportError(@"Couldn't install the package."));
                return;
            }

            [packageManager reloadInstalledPackages];
            completion(summary, replaced, nil);
        });
    });
}

// manifest.json at the top level, or inside exactly one top-level folder.
+ (nullable NSString *)packageRootInExtractedDirectory:(NSString *)extracted fileManager:(NSFileManager *)fm {
    if ([fm fileExistsAtPath:[extracted stringByAppendingPathComponent:@"manifest.json"]]) {
        return extracted;
    }
    NSMutableArray<NSString *> *visible = [NSMutableArray array];
    for (NSString *entry in [fm contentsOfDirectoryAtPath:extracted error:nil]) {
        if (![entry hasPrefix:@"."]) {
            [visible addObject:entry];
        }
    }
    if (visible.count != 1) {
        return nil;
    }
    NSString *inner = [extracted stringByAppendingPathComponent:visible.firstObject];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:inner isDirectory:&isDir] && isDir &&
        [fm fileExistsAtPath:[inner stringByAppendingPathComponent:@"manifest.json"]]) {
        return inner;
    }
    return nil;
}

// A pushed package (push_package.sh) may live in a directory whose name differs
// from its packageId, so match on the manifest, not the folder name.
+ (nullable NSString *)directoryInPackagesDir:(NSString *)packagesDir
                                 forPackageId:(NSString *)packageId
                                  fileManager:(NSFileManager *)fm {
    for (NSString *entry in [fm contentsOfDirectoryAtPath:packagesDir error:nil]) {
        NSString *dir = [packagesDir stringByAppendingPathComponent:entry];
        NSData *data = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"manifest.json"]];
        if (!data) {
            continue;
        }
        NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([manifest isKindOfClass:[NSDictionary class]] &&
            [manifest[@"packageId"] isEqual:packageId]) {
            return dir;
        }
    }
    return nil;
}

@end
