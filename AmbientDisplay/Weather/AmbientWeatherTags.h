#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The fixed weather-tag vocabulary. Not user-editable: package authors tag
/// scenes with these strings (see Docs/WEATHER_TAGS.md). Pure functions only.
///
/// Conditions: sunny cloudy foggy rainy snowy stormy
/// Periods:    day night
/// Valid tags: "<period>-<condition>" (e.g. day-rainy), "<condition>" (any time of day), "any"
@interface AmbientWeatherTags : NSObject

/// Any WMO code -> one of the six conditions. Unrecognised codes -> "cloudy".
+ (NSString *)conditionForWMOCode:(NSInteger)wmoCode;

/// Ordered, most specific first: @[@"day-rainy", @"rainy", @"any"].
+ (NSArray<NSString *> *)candidateTagsForWMOCode:(NSInteger)wmoCode isDay:(BOOL)isDay;

/// All 19 valid tags, for validating scene manifests.
+ (NSArray<NSString *> *)allValidTags;

@end

NS_ASSUME_NONNULL_END
