//
//  AppDelegate.m
//  AmbientDisplay
//
//  Created by Lambda on 9/2/26.
//

#import "AppDelegate.h"
#import "PackageManager.h"
#import "AudioEngineManager.h"

@interface AppDelegate ()

@property (nonatomic, strong, readwrite) AudioEngineManager *audioEngine;

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. Create the UIWindow manually to span the entire iPhone 6 Retina display
    NSLog(@"[AppDelegate] didFinishLaunchingWithOptions running");
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    // 2. Own playback for the app's whole lifetime. It's fine that
    //    PackageManager may not have an active playlist yet at this point —
    //    AudioEngineManager observes activePlaylistId via KVO and hard-cuts
    //    into the real playlist once ViewController's viewDidLoad calls
    //    reloadInstalledPackages / loadActiveTheme and that value lands.
    self.audioEngine = [[AudioEngineManager alloc] initWithPackageManager:[PackageManager sharedManager]];

    // 3. Load the initial ViewController from Main.storyboard
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    self.window.rootViewController = [storyboard instantiateInitialViewController];
    [self.window makeKeyAndVisible];

    // 4. Keep the display awake indefinitely so the desk clock stays illuminated
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    return YES;
}


#pragma mark - UISceneSession lifecycle


@end
