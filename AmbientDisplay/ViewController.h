#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@class PackageManager;

NS_ASSUME_NONNULL_BEGIN

@interface ViewController : UIViewController

@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) PackageManager *packageManager;

@end

NS_ASSUME_NONNULL_END
