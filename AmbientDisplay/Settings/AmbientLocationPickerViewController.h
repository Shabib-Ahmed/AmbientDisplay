#import <UIKit/UIKit.h>

@class AmbientLocationStore;
@class AmbientWeatherLocation;

NS_ASSUME_NONNULL_BEGIN

/// Pushed from the settings screen. Type a city, press Search, tap a result.
/// The choice is saved to weather-settings.json before `onSelect` runs.
@interface AmbientLocationPickerViewController : UITableViewController

- (instancetype)initWithLocationStore:(AmbientLocationStore *)store
                             onSelect:(void (^)(AmbientWeatherLocation *location))onSelect;

- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
