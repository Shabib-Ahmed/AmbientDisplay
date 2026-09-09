#import <XCTest/XCTest.h>
#import "ViewController.h"
#import "ThemeManager.h"

@interface ViewControllerTests : XCTestCase
@property (nonatomic, strong) NSString *tempBasePath;
@property (nonatomic, strong) ThemeManager *themeManager;
@property (nonatomic, strong) ViewController *sut;
@end

@implementation ViewControllerTests

- (void)setUp {
    [super setUp];
    NSString *unique = [NSString stringWithFormat:@"ViewControllerTests-%@", [[NSUUID UUID] UUIDString]];
    self.tempBasePath = [NSTemporaryDirectory() stringByAppendingPathComponent:unique];
    self.themeManager = [[ThemeManager alloc] initWithBaseDirectoryPath:self.tempBasePath];

    self.sut = [[ViewController alloc] initWithNibName:nil bundle:nil];
    self.sut.themeManager = self.themeManager;
    [self.sut loadViewIfNeeded];            
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempBasePath error:nil];
    self.sut = nil;
    self.themeManager = nil;
    [super tearDown];
}

- (void)testLoadActiveTheme_noIndexHTML_doesNotLoadWebView {
    [self.sut loadActiveTheme];
    XCTAssertNil(self.sut.webView.URL);
}

- (void)testLoadActiveTheme_withIndexHTML_loadsFileURL {
    NSURL *themeDir = [self.themeManager ensureActiveThemeDirectoryExists];
    NSString *indexPath = [themeDir.path stringByAppendingPathComponent:@"index.html"];
    [@"<html><body>Test theme</body></html>" writeToFile:indexPath
                                                atomically:YES
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];

    [self.sut loadActiveTheme];
    XCTAssertEqualObjects(self.sut.webView.URL.path, indexPath);
}

- (void)testThemeManager_defaultsToSharedManagerWhenNotInjected {
    ViewController *vc = [[ViewController alloc] initWithNibName:nil bundle:nil];
    XCTAssertEqualObjects(vc.themeManager, [ThemeManager sharedManager]);
}

@end
