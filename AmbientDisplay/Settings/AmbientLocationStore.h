#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AmbientWeatherLocation : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, assign, readonly) double latitude;
@property (nonatomic, assign, readonly) double longitude;

- (instancetype)initWithName:(NSString *)name latitude:(double)latitude longitude:(double)longitude;

@end

/// Reads and writes the `location` entry of Documents/AmbientDisplay/weather-settings.json
/// (the file AmbientWeatherThemeController re-reads on every poll), and searches
/// Open-Meteo's free geocoding API (no key) for cities.
@interface AmbientLocationStore : NSObject

- (instancetype)initWithBaseDirectory:(NSString *)baseDirectory;

- (nullable AmbientWeatherLocation *)currentLocation;

/// Merges into the existing file (other keys are preserved) and writes atomically.
- (BOOL)saveLocation:(AmbientWeatherLocation *)location error:(NSError **)error;

/// Completion is delivered on the main queue. Cancel the returned task to abandon a stale search.
- (NSURLSessionDataTask *)searchPlacesNamed:(NSString *)query
                                 completion:(void (^)(NSArray<AmbientWeatherLocation *> * _Nullable results,
                                                      NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
