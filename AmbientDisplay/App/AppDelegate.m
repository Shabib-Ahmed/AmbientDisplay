//
//  AppDelegate.m
//  AmbientDisplay
//
//  Created by Lambda on 9/2/26.
//

#import "AppDelegate.h"
#import "PackageManager.h"
#import "AudioEngineManager.h"
#import "AmbientWeatherThemeController.h"
#import <AVFoundation/AVFoundation.h>

@interface AppDelegate ()

@property (nonatomic, strong, readwrite) AudioEngineManager *audioEngine;
@property (nonatomic, strong, readwrite) AmbientWeatherThemeController *weatherController;

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. Create the UIWindow manually to span the entire iPhone 6 Retina display
    NSLog(@"[AppDelegate] didFinishLaunchingWithOptions running");
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    // 2. Load installed packages and resolve which theme should be active
    //    (falling back to the first installed theme, and re-syncing its
    //    playlist if needed) before anything else touches PackageManager.
    //    This used to happen in ViewController's viewDidLoad, which meant
    //    playback couldn't start until the view controller loaded; doing it
    //    here lets audio start as soon as the app launches.
    PackageManager *packageManager = [PackageManager sharedManager];
    [packageManager reloadInstalledPackages];
    [packageManager resolveActiveThemeWithFallback];

    // 2b. Configure the audio session *before* the engine exists. The default
    //     category (SoloAmbient) follows the silent switch and stops on lock;
    //     a desk clock wants Playback. AudioEngineManager's initializer
    //     starts the engine, so this must come first.
    NSError *sessionError = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryPlayback error:&sessionError] ||
        ![session setActive:YES error:&sessionError]) {
        NSLog(@"[AppDelegate] audio session setup failed: %@", sessionError);
    }

    // 3. Own playback for the app's whole lifetime. AudioEngineManager
    //    observes activePlaylistId via KVO and hard-cuts into whatever
    //    playlist resolution above landed on (or into a later one, if the
    //    user changes themes afterwards).
    self.audioEngine = [[AudioEngineManager alloc] initWithPackageManager:packageManager];

    // 4. Load the initial ViewController from Main.storyboard
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    self.window.rootViewController = [storyboard instantiateInitialViewController];
    [self.window makeKeyAndVisible];

    // 5. Keep the display awake indefinitely so the desk clock stays illuminated
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    // 6. Weather-driven theme switching. Acts only while
    //    packageManager.weatherAutoTheme is YES (observed live). Created after
    //    the view controller exists so a switch is picked up by its KVO
    //    observation of activeThemeId. Foreground-only: no Background Modes.
    //    The city comes from weather-settings.json (no GPS, no permission prompt).
    NSString *baseDir = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
                         stringByAppendingPathComponent:@"AmbientDisplay"];
    self.weatherController = [[AmbientWeatherThemeController alloc] initWithPackageManager:packageManager
                                                                              baseDirectory:baseDir];
    [self.weatherController start];

#if DEBUG
    // Debug: tap anywhere to flip between day-sunny and day-rainy.
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(debugTap)];
    tap.cancelsTouchesInView = NO;
    [self.window addGestureRecognizer:tap];
#endif

    return YES;
}

#if DEBUG
- (void)debugTap {
    static BOOL rainy = NO;
    rainy = !rainy;
    [self.weatherController debugApplyTag:rainy ? @"day-rainy" : @"day-sunny"];
}
#endif

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Timers don't fire while suspended; catch up on return to the foreground.
    [self.weatherController refreshNow];
}


#pragma mark - UISceneSession lifecycle


@end
