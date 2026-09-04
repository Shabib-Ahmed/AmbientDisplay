//
//  AppDelegate.m
//  AmbientDisplay
//
//  Created by Lambda on 9/2/26.
//

#import "AppDelegate.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 1. Create the UIWindow manually to span the entire iPhone 6 Retina display
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    
    // 2. Load the initial ViewController from Main.storyboard
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    self.window.rootViewController = [storyboard instantiateInitialViewController];
    [self.window makeKeyAndVisible];
    
    // 3. Keep the display awake indefinitely so the desk clock stays illuminated
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    return YES;
}


#pragma mark - UISceneSession lifecycle


@end
