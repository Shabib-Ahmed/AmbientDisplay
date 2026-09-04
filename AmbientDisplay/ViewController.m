//
//  ViewController.m
//  AmbientDisplay
//
//  Created by Lambda on 9/2/26.
//

#import "ViewController.h"
#import "ThemeManager.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"[AmbientDisplay] viewDidLoad START");
    NSLog(@"[AmbientDisplay] Home directory: %@", NSHomeDirectory());
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:[[WKWebViewConfiguration alloc] init]];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.webView];

    NSURL *readAccessURL = [[ThemeManager sharedManager] ensureActiveThemeDirectoryExists];
    NSURL *indexURL = [[ThemeManager sharedManager] activeThemeIndexURL];

    if (indexURL) {
        [self.webView loadFileURL:indexURL allowingReadAccessToURL:readAccessURL];
    } else {
        NSLog(@"[AmbientDisplay] No theme found");
    }
}


@end
