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
