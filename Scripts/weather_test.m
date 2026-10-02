// Command-line harness for the weather code (Foundation only, runs on macOS).
// Usage: Scripts/weather_test.sh [latitude longitude]     (default: Cleveland, Ohio)
#import <Foundation/Foundation.h>
#import "AmbientWeatherTags.h"
#import "AmbientWeatherConditions.h"
#import "AmbientWeatherService.h"

static int failures = 0;

static void expectCondition(NSInteger code, NSString *expected) {
    NSString *got = [AmbientWeatherTags conditionForWMOCode:code];
    BOOL ok = [got isEqualToString:expected];
    if (!ok) failures++;
    printf("  %s  wmo %3ld -> %-7s (expected %s)\n", ok ? "PASS" : "FAIL",
           (long)code, got.UTF8String, expected.UTF8String);
}

static void expectCandidates(NSInteger code, BOOL isDay, NSArray *expected) {
    NSArray *got = [AmbientWeatherTags candidateTagsForWMOCode:code isDay:isDay];
    BOOL ok = [got isEqualToArray:expected];
    if (!ok) failures++;
    printf("  %s  wmo %ld %s -> %s\n", ok ? "PASS" : "FAIL", (long)code, isDay ? "day  " : "night",
           [got componentsJoinedByString:@", "].UTF8String);
}

static void offlineTests(void) {
    printf("\n== Offline: WMO code -> condition ==\n");
    struct { NSInteger code; __unsafe_unretained NSString *cond; } table[] = {
        {0,@"sunny"},{1,@"sunny"},{2,@"cloudy"},{3,@"cloudy"},{45,@"foggy"},{48,@"foggy"},
        {51,@"rainy"},{53,@"rainy"},{55,@"rainy"},{56,@"rainy"},{57,@"rainy"},
        {61,@"rainy"},{63,@"rainy"},{65,@"rainy"},{66,@"rainy"},{67,@"rainy"},
        {71,@"snowy"},{73,@"snowy"},{75,@"snowy"},{77,@"snowy"},
        {80,@"rainy"},{81,@"rainy"},{82,@"rainy"},{85,@"snowy"},{86,@"snowy"},
        {95,@"stormy"},{96,@"stormy"},{99,@"stormy"},
        {4,@"cloudy"},{200,@"cloudy"},   // unrecognised -> cloudy
    };
    for (size_t i = 0; i < sizeof(table)/sizeof(table[0]); i++) expectCondition(table[i].code, table[i].cond);

    printf("\n== Offline: candidate lists ==\n");
    expectCandidates(63, YES, @[@"day-rainy", @"rainy", @"any"]);
    expectCandidates(71, NO,  @[@"night-snowy", @"snowy", @"any"]);
    expectCandidates(0,  YES, @[@"day-sunny", @"sunny", @"any"]);
    expectCandidates(96, NO,  @[@"night-stormy", @"stormy", @"any"]);

    printf("\n== Offline: valid tag list ==\n");
    NSArray *all = [AmbientWeatherTags allValidTags];
    BOOL ok = all.count == 19 && [NSSet setWithArray:all].count == 19 &&
              [all containsObject:@"night-stormy"] && [all containsObject:@"any"];
    if (!ok) failures++;
    printf("  %s  %lu tags: %s\n", ok ? "PASS" : "FAIL", (unsigned long)all.count,
           [all componentsJoinedByString:@" "].UTF8String);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        double lat = 41.4993, lon = -81.6944;   // Cleveland, Ohio
        if (argc >= 3) { lat = atof(argv[1]); lon = atof(argv[2]); }

        offlineTests();
        printf("\nOffline result: %s\n", failures ? "FAILURES" : "all passed");

        printf("\n== Live: Open-Meteo for (%.4f, %.4f) ==\n", lat, lon);
        AmbientWeatherService *service = [[AmbientWeatherService alloc] init];
        [service fetchConditionsForLatitude:lat longitude:lon
                                 completion:^(AmbientWeatherConditions *c, NSError *error) {
            if (!c) {
                printf("  FAIL  fetch error: %s\n", error.description.UTF8String);
                exit(2);
            }
            printf("  raw        wmo=%ld isDay=%d\n", (long)c.wmoCode, c.isDay);
            printf("  condition  %s\n", [AmbientWeatherTags conditionForWMOCode:c.wmoCode].UTF8String);
            printf("  candidates %s\n", [[AmbientWeatherTags candidateTagsForWMOCode:c.wmoCode isDay:c.isDay]
                                         componentsJoinedByString:@", "].UTF8String);
            printf("\nCross-check against the raw API:\n  curl -s \"https://api.open-meteo.com/v1/forecast?latitude=%.3f&longitude=%.3f&current=weather_code,is_day\"\n",
                   lat, lon);
            exit(failures ? 1 : 0);
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            printf("  FAIL  timed out\n");
            exit(2);
        });
        dispatch_main();   // the service calls back on the main queue
    }
}
