#import <Foundation/Foundation.h>

@class AmbientWeatherConditions;

NS_ASSUME_NONNULL_BEGIN

/// Always invoked on the main queue.
typedef void (^AmbientWeatherServiceCompletion)(AmbientWeatherConditions * _Nullable conditions,
                                                NSError * _Nullable error);

/// Open-Meteo client (free, no key, global). Returns raw conditions only;
/// mapping to tags is AmbientWeatherTags' job.
@interface AmbientWeatherService : NSObject

- (void)fetchConditionsForLatitude:(double)latitude
                         longitude:(double)longitude
                        completion:(AmbientWeatherServiceCompletion)completion;

@end

NS_ASSUME_NONNULL_END
