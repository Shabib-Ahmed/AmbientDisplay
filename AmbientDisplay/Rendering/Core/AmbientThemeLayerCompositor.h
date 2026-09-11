#import <UIKit/UIKit.h>
#import "AmbientAudioDataSource.h"

@class AmbientTheme;

NS_ASSUME_NONNULL_BEGIN

// A single view, sized to fill the area above the background video, that
// owns the full stack of layer renderers for the current theme. Add this
// as a subview above ViewController's backgroundPlayerLayer once; from
// then on, loadTheme: is the only entry point ViewController needs.
@interface AmbientThemeLayerCompositor : UIView

- (instancetype)initWithFrame:(CGRect)frame
               audioDataSource:(nullable id<AmbientAudioDataSource>)audioDataSource NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

// Tears down and stops every currently-rendered layer, then builds fresh
// renderers for theme.layers in order (array index 0 is added first, so
// it sits at the bottom, directly above the background video; later
// entries stack on top - this is how a package places effects both
// behind and in front of the clock). Passing nil just clears everything,
// leaving nothing but the background video visible.
//
// Same hard-cut philosophy as playlist/background-video switching
// elsewhere in the app - no attempt to diff against the previous theme
// or transition smoothly between them.
- (void)loadTheme:(nullable AmbientTheme *)theme;

@end

NS_ASSUME_NONNULL_END
