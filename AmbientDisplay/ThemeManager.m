//
//  ThemeManager.m
//  AmbientDisplay
//
//  Created by Lambda on 9/4/26.
//
#import "ThemeManager.h"

@implementation ThemeManager

+ (instancetype)sharedManager {

    static ThemeManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ThemeManager alloc] init];
    });
    return instance;
}

- (NSString *)themeDirPath{
    return @"/var/mobile/Documents/AmbientDisplay/Themes/Active";
}

- (NSURL *)ensureActiveThemeDirectoryExists {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [self themeDirPath];

    BOOL isDir;
    BOOL exists = [fm fileExistsAtPath:path isDirectory:&isDir];
    NSLog(@"[ThemeManager] Checking path: %@ (exists=%d isDir=%d)", path, exists, isDir);

    if (!exists) {
        NSError *error = nil;
        BOOL created = [fm createDirectoryAtPath:path
                      withIntermediateDirectories:YES
                                       attributes:nil
                                            error:&error];
        NSLog(@"[ThemeManager] createDirectoryAtPath returned: %d, error: %@", created, error);
    }
    return [NSURL fileURLWithPath:path];
}

- (NSURL *)activeThemeIndexURL{
    NSString *indexPath = [[self themeDirPath] stringByAppendingPathComponent:@"index.html"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:indexPath]){
        return [NSURL fileURLWithPath:indexPath];
    }
    return nil; 
}

@end
