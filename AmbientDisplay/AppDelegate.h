#import <UIKit/UIKit.h>

@class AudioEngineManager;

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong, readonly) AudioEngineManager *audioEngine;

@end

NS_ASSUME_NONNULL_END
