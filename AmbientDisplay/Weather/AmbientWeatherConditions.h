#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Raw observed conditions. Deliberately knows nothing about tags.
@interface AmbientWeatherConditions : NSObject

@property (nonatomic, readonly) NSInteger wmoCode;
@property (nonatomic, readonly) BOOL isDay;

+ (instancetype)conditionsWithWMOCode:(NSInteger)wmoCode isDay:(BOOL)isDay;

@end

NS_ASSUME_NONNULL_END
