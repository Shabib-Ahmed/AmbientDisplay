#import <UIKit/UIKit.h>

@class AudioEngineManager;

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;

/// Owns playback for the app's lifetime, independent of whatever view
/// controller happens to be on screen. Wraps PackageManager.sharedManager
/// and hard-cuts automatically whenever the active playlist changes.
@property (nonatomic, strong, readonly) AudioEngineManager *audioEngine;

@end

NS_ASSUME_NONNULL_END
