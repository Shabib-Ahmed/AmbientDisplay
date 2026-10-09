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
#import "AmbientSettingsViewController.h"
#import "AmbientLocationStore.h"
#import "AmbientPackageImporter.h"
#import <AVFoundation/AVFoundation.h>

@interface AppDelegate ()

@property (nonatomic, strong, readwrite) AudioEngineManager *audioEngine;
@property (nonatomic, strong, readwrite) AmbientWeatherThemeController *weatherController;
@property (nonatomic, strong) AmbientLocationStore *locationStore;

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

    // 7. Settings. Long-press anywhere opens the settings menu. This replaces
    //    the old DEBUG tap-to-toggle-weather gesture, which is gone.
    //    allowableMovement is generous because a finger held on a phone
    //    sitting on a desk drifts well past the 10pt default over a full second,
    //    which silently cancels the recognizer.
    self.locationStore = [[AmbientLocationStore alloc] initWithBaseDirectory:baseDir];
    UILongPressGestureRecognizer *press =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(openSettings:)];
    press.minimumPressDuration = 0.8;
    press.allowableMovement = 60;
    press.cancelsTouchesInView = NO;
    [self.window addGestureRecognizer:press];

    return YES;
}

- (void)openSettings:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    NSLog(@"[AppDelegate] long press recognized");

    UIViewController *root = self.window.rootViewController;
    if (root.presentedViewController) {
        NSLog(@"[AppDelegate] settings already presented, ignoring");
        return;
    }

    AmbientSettingsViewController *settings =
        [[AmbientSettingsViewController alloc] initWithPackageManager:[PackageManager sharedManager]
                                                    weatherController:self.weatherController
                                                        locationStore:self.locationStore];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    [root presentViewController:nav animated:YES completion:nil];
}

// AirDrop / Filza / share-sheet "Open in AmbientDisplay" for a .zip package.
// Needs the CFBundleDocumentTypes entry in Info.plist. iOS copies the file into
// Documents/Inbox first (we don't claim open-in-place), so it is safe to delete after.
- (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    if (!url.isFileURL || ![url.pathExtension.lowercaseString isEqualToString:@"zip"]) {
        return NO;
    }
    NSLog(@"[AppDelegate] open-in zip: %@", url.lastPathComponent);

    [AmbientPackageImporter importZipAtURL:url
                            packageManager:[PackageManager sharedManager]
                                completion:^(NSString *summary, BOOL replaced, NSError *error) {
        // Only delete our own Inbox copy, never a file opened in place.
        if ([url.path containsString:@"/Documents/Inbox/"]) {
            [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
        }
        if (!error) {
            [self.weatherController refreshNow];
        }

        UIViewController *top = self.window.rootViewController;
        while (top.presentedViewController) {
            top = top.presentedViewController;
        }
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:error ? @"Import failed"
                                                             : (replaced ? @"Package updated" : @"Package installed")
                                                message:error ? error.localizedDescription : summary
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    }];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Timers don't fire while suspended; catch up on return to the foreground.
    [self.weatherController refreshNow];
}


#pragma mark - UISceneSession lifecycle


@end
