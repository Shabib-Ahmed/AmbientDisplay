#import <UIKit/UIKit.h>

@class AudioEngineManager, AmbientWeatherThemeController;

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong, readonly) AudioEngineManager *audioEngine;
@property (nonatomic, strong, readonly) AmbientWeatherThemeController *weatherController;

@end

NS_ASSUME_NONNULL_END
