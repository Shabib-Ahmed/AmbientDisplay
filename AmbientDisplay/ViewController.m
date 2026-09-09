#import "ViewController.h"
#import "PackageManager.h"

@interface ViewController ()
@end

@implementation ViewController

- (PackageManager *)packageManager{
    if (!_packageManager){
        _packageManager = [PackageManager sharedManager];
    }
    return _packageManager;
}

- (void)viewDidLoad{
    [super viewDidLoad];
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:[[WKWebViewConfiguration alloc] init]];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    [self.view addSubview:self.webView];
    [self.packageManager reloadInstalledPackages];
    [self loadActiveTheme];
}

- (void)loadActiveTheme{
    AmbientTheme *theme = self.packageManager.activeTheme;
    if (theme){
        [self.webView loadFileURL:theme.entryPointURL allowingReadAccessToURL:theme.readAccessURL];

        // setActiveThemeId: is the only place PackageManager re-syncs the
        // playlist for a package (see syncPlaylistWithTheme in PackageManager.m).
        // If the theme was already active from a previous launch's state.json
        // but no playlist ever got synced (e.g. it had zero valid tracks back
        // then), re-trigger that sync now that the package may have been fixed.
        if (!self.packageManager.activePlaylist) {
            [self.packageManager setActiveThemeId:theme.themeId error:nil];
        }
        return;
    }
    
    
    AmbientTheme *fallback = self.packageManager.installedThemes.firstObject;
        if (fallback) {
            NSError *error = nil;
            if ([self.packageManager setActiveThemeId:fallback.themeId error:&error]) {
                [self loadActiveTheme];
            } else {
                NSLog(@"[AmbientDisplay] failed to activate fallback theme: %@", error);
            }
            return;
        }
     
        NSLog(@"[AmbientDisplay] No themes installed");
}

@end
