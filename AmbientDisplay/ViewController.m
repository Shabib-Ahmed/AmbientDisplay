#import "ViewController.h"
#import "PackageManager.h"
#import "AmbientThemeLayerCompositor.h"
#import "AppDelegate.h"
#import "AudioEngineManager.h"
#import <AVFoundation/AVFoundation.h>

@interface ViewController ()

@property (nonatomic, strong) AVQueuePlayer *backgroundPlayer;
@property (nonatomic, strong) AVPlayerLooper *backgroundLooper;
@property (nonatomic, strong) AVPlayerLayer *backgroundPlayerLayer;

@property (nonatomic, strong) AmbientThemeLayerCompositor *themeLayerCompositor;
@property (nonatomic, copy, nullable) NSString *loadedThemeId;

@end

@implementation ViewController

- (PackageManager *)packageManager {
    if (!_packageManager) {
        _packageManager = [PackageManager sharedManager];
    }
    return _packageManager;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.backgroundPlayerLayer = [AVPlayerLayer layer];
    self.backgroundPlayerLayer.frame = self.view.bounds;
    self.backgroundPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer:self.backgroundPlayerLayer];

  
    AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    self.themeLayerCompositor = [[AmbientThemeLayerCompositor alloc] initWithFrame:self.view.bounds
                                                                     audioDataSource:appDelegate.audioEngine];
    self.themeLayerCompositor.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.themeLayerCompositor];

    [self.packageManager addObserver:self
                           forKeyPath:@"activeThemeId"
                              options:0
                              context:NULL];

    [self reloadBackgroundForActiveTheme];
}

- (void)dealloc {
    [self.packageManager removeObserver:self forKeyPath:@"activeThemeId"];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.backgroundPlayerLayer.frame = self.view.bounds;
}

#pragma mark - KVO (hard-cut on theme change)

- (void)observeValueForKeyPath:(nullable NSString *)keyPath
                       ofObject:(nullable id)object
                         change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change
                        context:(nullable void *)context {
    if (object == self.packageManager && [keyPath isEqualToString:@"activeThemeId"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadBackgroundForActiveTheme];
        });
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

#pragma mark - Background video

- (void)reloadBackgroundForActiveTheme {
    // resolveActiveThemeWithFallback: defaults to the first installed theme
    // when nothing has been explicitly chosen, and only returns nil when
    // there's genuinely no theme package installed. It may call
    // setActiveThemeId: under us, which re-triggers this method via our own
    // KVO observation - the loadedThemeId check below makes that redundant
    // second call a no-op instead of restarting the video.
    AmbientTheme *theme = [self.packageManager resolveActiveThemeWithFallback];

    if (theme && [theme.themeId isEqualToString:self.loadedThemeId]) {
        return;
    }

    [self.backgroundPlayer pause];
    self.backgroundPlayer = nil;
    self.backgroundLooper = nil;
    self.backgroundPlayerLayer.player = nil;

    if (!theme) {
        NSLog(@"[AmbientDisplay] No active theme to load");
        self.loadedThemeId = nil;
        [self.themeLayerCompositor loadTheme:nil];
        return;
    }

    self.loadedThemeId = theme.themeId;

    AVQueuePlayer *player = [[AVQueuePlayer alloc] init];
    player.muted = YES;

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:theme.backgroundVideoURL];
    self.backgroundLooper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:item];

    self.backgroundPlayer = player;
    self.backgroundPlayerLayer.player = player;
    [player play];


    [self.themeLayerCompositor loadTheme:theme];

    NSLog(@"[AmbientDisplay] loaded background video for theme %@: %@",
          theme.themeId, theme.backgroundVideoURL.lastPathComponent);
}

@end
