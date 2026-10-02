#import "AmbientWeatherTags.h"

@implementation AmbientWeatherTags

+ (NSArray<NSString *> *)conditions {
    return @[@"sunny", @"cloudy", @"foggy", @"rainy", @"snowy", @"stormy"];
}

+ (NSString *)conditionForWMOCode:(NSInteger)c {
    if (c == 0 || c == 1)                 return @"sunny";    // clear, mainly clear
    if (c == 2 || c == 3)                 return @"cloudy";   // partly cloudy, overcast
    if (c == 45 || c == 48)               return @"foggy";    // fog, rime fog
    if (c >= 51 && c <= 67)               return @"rainy";    // drizzle, rain, freezing drizzle/rain
    if (c >= 71 && c <= 77)               return @"snowy";    // snow fall, snow grains
    if (c >= 80 && c <= 82)               return @"rainy";    // rain showers
    if (c == 85 || c == 86)               return @"snowy";    // snow showers
    if (c >= 95 && c <= 99)               return @"stormy";   // thunderstorm (incl. hail)
    return @"cloudy";                                         // anything unexpected
}

+ (NSArray<NSString *> *)candidateTagsForWMOCode:(NSInteger)wmoCode isDay:(BOOL)isDay {
    NSString *condition = [self conditionForWMOCode:wmoCode];
    NSString *period = isDay ? @"day" : @"night";
    return @[[NSString stringWithFormat:@"%@-%@", period, condition], condition, @"any"];
}

+ (NSArray<NSString *> *)allValidTags {
    NSMutableArray *tags = [NSMutableArray arrayWithObject:@"any"];
    for (NSString *c in [self conditions]) {
        [tags addObject:c];
        [tags addObject:[@"day-" stringByAppendingString:c]];
        [tags addObject:[@"night-" stringByAppendingString:c]];
    }
    return tags;
}

@end
