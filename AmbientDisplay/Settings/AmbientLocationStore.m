#import "AmbientLocationStore.h"

@implementation AmbientWeatherLocation

- (instancetype)initWithName:(NSString *)name latitude:(double)latitude longitude:(double)longitude {
    self = [super init];
    if (self) {
        _name = [name copy];
        _latitude = latitude;
        _longitude = longitude;
    }
    return self;
}

@end

@interface AmbientLocationStore ()
@property (nonatomic, copy) NSString *filePath;
@end

@implementation AmbientLocationStore

- (instancetype)initWithBaseDirectory:(NSString *)baseDirectory {
    self = [super init];
    if (self) {
        _filePath = [baseDirectory stringByAppendingPathComponent:@"weather-settings.json"];
    }
    return self;
}

- (nullable NSDictionary *)readFile {
    NSData *data = [NSData dataWithContentsOfFile:self.filePath];
    if (!data) {
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

- (nullable AmbientWeatherLocation *)currentLocation {
    NSDictionary *loc = [self readFile][@"location"];
    if (![loc isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *name = loc[@"name"];
    NSNumber *lat = loc[@"latitude"];
    NSNumber *lon = loc[@"longitude"];
    if (![name isKindOfClass:[NSString class]] ||
        ![lat isKindOfClass:[NSNumber class]] ||
        ![lon isKindOfClass:[NSNumber class]]) {
        return nil;
    }
    return [[AmbientWeatherLocation alloc] initWithName:name latitude:lat.doubleValue longitude:lon.doubleValue];
}

- (BOOL)saveLocation:(AmbientWeatherLocation *)location error:(NSError **)error {
    NSMutableDictionary *file = [[self readFile] mutableCopy] ?: [NSMutableDictionary dictionary];
    file[@"location"] = @{
        @"name": location.name,
        @"latitude": @(location.latitude),
        @"longitude": @(location.longitude),
    };

    NSData *data = [NSJSONSerialization dataWithJSONObject:file options:NSJSONWritingPrettyPrinted error:error];
    if (!data) {
        return NO;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:[self.filePath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return [data writeToFile:self.filePath options:NSDataWritingAtomic error:error];
}

#pragma mark Search

- (NSURLSessionDataTask *)searchPlacesNamed:(NSString *)query
                                 completion:(void (^)(NSArray<AmbientWeatherLocation *> * _Nullable,
                                                      NSError * _Nullable))completion {
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"https";
    components.host = @"geocoding-api.open-meteo.com";
    components.path = @"/v1/search";
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"name" value:query],
        [NSURLQueryItem queryItemWithName:@"count" value:@"10"],
        [NSURLQueryItem queryItemWithName:@"language" value:@"en"],
        [NSURLQueryItem queryItemWithName:@"format" value:@"json"],
    ];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    request.timeoutInterval = 15;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
            NSArray<AmbientWeatherLocation *> *results = nil;
            NSError *failure = networkError;

            if (!failure) {
                NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
                    ? ((NSHTTPURLResponse *)response).statusCode : 200;
                id json = (data && status == 200) ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                if (![json isKindOfClass:[NSDictionary class]]) {
                    failure = [NSError errorWithDomain:@"AmbientLocationStore" code:1
                                              userInfo:@{NSLocalizedDescriptionKey: @"The search service returned an unexpected response."}];
                } else {
                    // "results" is absent (not empty) when nothing matched.
                    NSArray *raw = json[@"results"];
                    NSMutableArray *parsed = [NSMutableArray array];
                    if ([raw isKindOfClass:[NSArray class]]) {
                        for (NSDictionary *item in raw) {
                            if (![item isKindOfClass:[NSDictionary class]]) { continue; }
                            NSString *name = item[@"name"];
                            NSNumber *lat = item[@"latitude"];
                            NSNumber *lon = item[@"longitude"];
                            if (![name isKindOfClass:[NSString class]] ||
                                ![lat isKindOfClass:[NSNumber class]] ||
                                ![lon isKindOfClass:[NSNumber class]]) { continue; }

                            NSString *admin1 = [item[@"admin1"] isKindOfClass:[NSString class]] ? item[@"admin1"] : nil;
                            NSString *country = [item[@"country"] isKindOfClass:[NSString class]] ? item[@"country"] : nil;
                            BOOL isUS = [[item[@"country_code"] description] isEqualToString:@"US"];

                            // "Cleveland, Ohio" for the US (matches the placeholder), else "City, Region, Country".
                            NSMutableArray *parts = [NSMutableArray arrayWithObject:name];
                            if (admin1.length && ![admin1 isEqualToString:name]) { [parts addObject:admin1]; }
                            if (!isUS && country.length) { [parts addObject:country]; }

                            [parsed addObject:[[AmbientWeatherLocation alloc]
                                initWithName:[parts componentsJoinedByString:@", "]
                                    latitude:lat.doubleValue
                                   longitude:lon.doubleValue]];
                        }
                    }
                    results = [parsed copy];
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                // A cancelled search is stale; its caller no longer cares.
                if ([failure.domain isEqualToString:NSURLErrorDomain] && failure.code == NSURLErrorCancelled) {
                    return;
                }
                completion(failure ? nil : results, failure);
            });
        }];
    [task resume];
    return task;
}

@end
