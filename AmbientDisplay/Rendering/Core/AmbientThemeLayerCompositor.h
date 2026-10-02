#import <UIKit/UIKit.h>
#import "AmbientAudioDataSource.h"

@class AmbientTheme;

NS_ASSUME_NONNULL_BEGIN

@interface AmbientThemeLayerCompositor : UIView

- (instancetype)initWithFrame:(CGRect)frame
               audioDataSource:(nullable id<AmbientAudioDataSource>)audioDataSource NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;


- (void)loadTheme:(nullable AmbientTheme *)theme;

@end

NS_ASSUME_NONNULL_END
