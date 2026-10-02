#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "AmbientAudioDataSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface AmbientAudioLevelsTextureProvider : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>)device
                 canonicalWidth:(NSUInteger)canonicalWidth NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, weak, nullable) id<AmbientAudioDataSource> audioDataSource;
@property (nonatomic, assign) CGFloat smoothing;    // default 0.85 (ported kDefaultSmoothing)
@property (nonatomic, assign) CGFloat sensitivity;  // default 1.0, clamped to 0...10 on set

// R32Float, canonicalWidth x 1. nil until the first -tick call.
@property (nonatomic, strong, readonly, nullable) id<MTLTexture> texture;

- (void)tick;

@end

NS_ASSUME_NONNULL_END
