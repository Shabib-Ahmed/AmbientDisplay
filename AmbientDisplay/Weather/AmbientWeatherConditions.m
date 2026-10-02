#import "AmbientWeatherConditions.h"

@implementation AmbientWeatherConditions

+ (instancetype)conditionsWithWMOCode:(NSInteger)wmoCode isDay:(BOOL)isDay {
    AmbientWeatherConditions *c = [[AmbientWeatherConditions alloc] init];
    c->_wmoCode = wmoCode;
    c->_isDay = isDay;
    return c;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"wmo=%ld isDay=%d", (long)self.wmoCode, self.isDay];
}

@end
