//
//  ThemeManager.h
//  AmbientDisplay
//
//  Created by Lambda on 9/4/26.
//
#import <Foundation/Foundation.h>

@interface ThemeManager : NSObject

+ (instancetype)sharedManager;
- (NSURL *)ensureActiveThemeDirectoryExists;
- (NSURL *)activeThemeIndexURL;

@end
