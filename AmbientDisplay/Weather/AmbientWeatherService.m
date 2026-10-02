#import "AmbientWeatherService.h"
#import "AmbientWeatherConditions.h"

static NSString * const kWeatherErrorDomain = @"AmbientWeatherErrorDomain";

@implementation AmbientWeatherService

- (void)fetchConditionsForLatitude:(double)latitude
                         longitude:(double)longitude
                        completion:(AmbientWeatherServiceCompletion)completion {
    NSString *urlString = [NSString stringWithFormat:
        @"https://api.open-meteo.com/v1/forecast?latitude=%.3f&longitude=%.3f&current=weather_code,is_day",
        latitude, longitude];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:15];

    void (^finish)(AmbientWeatherConditions *, NSError *) = ^(AmbientWeatherConditions *c, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(c, e); });
    };

    [[[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? ((NSHTTPURLResponse *)response).statusCode : 0;
        if (error || status != 200 || !data) {
            finish(nil, error ?: [NSError errorWithDomain:kWeatherErrorDomain code:status userInfo:
                                  @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP %ld", (long)status]}]);
            return;
        }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *current = [json isKindOfClass:[NSDictionary class]] ? json[@"current"] : nil;
        NSNumber *code = [current isKindOfClass:[NSDictionary class]] ? current[@"weather_code"] : nil;
        NSNumber *isDay = [current isKindOfClass:[NSDictionary class]] ? current[@"is_day"] : nil;
        if (![code isKindOfClass:[NSNumber class]] || ![isDay isKindOfClass:[NSNumber class]]) {
            finish(nil, [NSError errorWithDomain:kWeatherErrorDomain code:-1 userInfo:
                         @{NSLocalizedDescriptionKey: @"Unexpected response shape"}]);
            return;
        }
        finish([AmbientWeatherConditions conditionsWithWMOCode:code.integerValue isDay:isDay.boolValue], nil);
    }] resume];
}

@end
