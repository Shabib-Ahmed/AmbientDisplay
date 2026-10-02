#import <Foundation/Foundation.h>

@class PackageManager;

NS_ASSUME_NONNULL_BEGIN

/// Polls weather for the user's chosen city (weather-settings.json), resolves
/// candidate tags, and switches the active theme via PackageManager.
/// Acts only while PackageManager.weatherAutoTheme is YES. Main thread only.
@interface AmbientWeatherThemeController : NSObject

/// baseDirectory = Documents/AmbientDisplay (where weather-settings.json lives).
- (instancetype)initWithPackageManager:(PackageManager *)packageManager
                         baseDirectory:(NSString *)baseDirectory NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)start;        // idempotent
- (void)stop;
- (void)refreshNow;

/// Test hook: suspends real polling for the rest of the session and applies a
/// literal tag through the normal switching logic. Ignores weatherAutoTheme.
- (void)debugApplyTag:(NSString *)tag;

@end

NS_ASSUME_NONNULL_END
