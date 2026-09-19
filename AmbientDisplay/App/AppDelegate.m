//
//  AppDelegate.m
//  AmbientDisplay
//
//  Created by Lambda on 9/2/26.
//

#import "AppDelegate.h"
#import "PackageManager.h"
#import "AudioEngineManager.h"
#import <AVFoundation/AVFoundation.h>

@interface AppDelegate ()

@property (nonatomic, strong, readwrite) AudioEngineManager *audioEngine;

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

    return YES;
}


#pragma mark - UISceneSession lifecycle


@end
