#import <UIKit/UIKit.h>

@class PackageManager;
@class AmbientWeatherThemeController;
@class AmbientLocationStore;

NS_ASSUME_NONNULL_BEGIN

/// The 1.0 settings screen. Present it inside a UINavigationController.
///
/// Sections: Weather (auto-theme switch, location), Theme (manual choice,
/// only enabled while weather matching is off), Music (playlist choice),
/// Packages (import a .zip).
@interface AmbientSettingsViewController : UITableViewController

- (instancetype)initWithPackageManager:(PackageManager *)packageManager
                     weatherController:(AmbientWeatherThemeController *)weatherController
                         locationStore:(AmbientLocationStore *)locationStore;

- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
