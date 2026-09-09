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
    [self loadActiveTheme];
}

- (void)loadActiveTheme{
    AmbientTheme *theme = self.packageManager.activeTheme;
    if (theme){
        [self.webView loadFileURL:theme.entryPointURL allowingReadAccessToURL:theme.readAccessURL];
    } else {
        NSLog(@"[AmbientDisplay] No active theme to load");
    }
}

@end
