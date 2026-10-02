#import "AmbientWeatherThemeController.h"
#import "PackageManager.h"
#import "AmbientWeatherService.h"
#import "AmbientWeatherConditions.h"
#import "AmbientWeatherTags.h"

static void *kAutoThemeContext = &kAutoThemeContext;
static NSString * const kSettingsFileName = @"weather-settings.json";
static const NSTimeInterval kPollInterval = 45 * 60;

@implementation AmbientWeatherThemeController {
    PackageManager *_pm;
    NSString *_baseDir;
    AmbientWeatherService *_service;
    NSString *_locationName;
    NSTimer *_timer;
    BOOL _started;
    BOOL _inFlight;
    BOOL _debugOverride;
    AmbientWeatherConditions *_lastConditions;
}

- (instancetype)initWithPackageManager:(PackageManager *)packageManager baseDirectory:(NSString *)baseDirectory {
    if ((self = [super init])) {
        _pm = packageManager;
        _baseDir = [baseDirectory copy];
        _service = [[AmbientWeatherService alloc] init];
    }
    return self;
}

- (void)dealloc { [self stop]; }

#pragma mark Lifecycle

- (void)start {
    if (_started) return;
    _started = YES;
    [_pm addObserver:self forKeyPath:@"weatherAutoTheme"
             options:NSKeyValueObservingOptionNew context:kAutoThemeContext];
    NSLog(@"[Weather] started (auto=%d)", _pm.weatherAutoTheme);
    NSArray<NSString *> *valid = [AmbientWeatherTags allValidTags];
    for (AmbientTheme *theme in _pm.installedThemes) {
        for (NSString *tag in theme.weatherTags) {
            if (![valid containsObject:tag]) {
                NSLog(@"[Weather] WARNING: theme %@ has unknown weather tag '%@' (it will never match)",
                      theme.themeId, tag);
            }
        }
    }
    [self refreshNow];
}

- (void)stop {
    [_timer invalidate];
    _timer = nil;
    if (_started) {
        [_pm removeObserver:self forKeyPath:@"weatherAutoTheme" context:kAutoThemeContext];
        _started = NO;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if (context != kAutoThemeContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_started || !self->_pm.weatherAutoTheme || self->_debugOverride) return;
        if (self->_lastConditions) [self evaluateConditions:self->_lastConditions];  // instant, from cache
        [self refreshNow];                                                           // then freshen
    });
}

#pragma mark Polling

- (void)scheduleNext {
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:kPollInterval
                                              target:self selector:@selector(refreshNow)
                                            userInfo:nil repeats:NO];
}

/// Reads the user's city from weather-settings.json on every call, so edits apply next cycle:
///   { "location": { "name": "Seattle", "latitude": 47.61, "longitude": -122.33 } }
- (BOOL)loadLocationLatitude:(double *)lat longitude:(double *)lon {
    NSString *path = [_baseDir stringByAppendingPathComponent:kSettingsFileName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        // First run: write a placeholder city. Never overwrites an existing file.
        // (Replace with a settings-menu city picker later.)
        NSDictionary *placeholder = @{@"location": @{@"name": @"Cleveland, Ohio",
                                                     @"latitude": @41.4993,
                                                     @"longitude": @-81.6944}};
        NSData *def = [NSJSONSerialization dataWithJSONObject:placeholder
                                                      options:NSJSONWritingPrettyPrinted error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:_baseDir withIntermediateDirectories:YES
                                                   attributes:nil error:nil];
        [def writeToFile:path options:NSDataWritingAtomic error:nil];
        NSLog(@"[Weather] wrote placeholder %@ (Cleveland, Ohio)", kSettingsFileName);
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *loc = [json isKindOfClass:[NSDictionary class]] ? json[@"location"] : nil;
    if (![loc isKindOfClass:[NSDictionary class]] ||
        ![loc[@"latitude"] isKindOfClass:[NSNumber class]] ||
        ![loc[@"longitude"] isKindOfClass:[NSNumber class]]) return NO;
    *lat = [loc[@"latitude"] doubleValue];
    *lon = [loc[@"longitude"] doubleValue];
    if (*lat < -90 || *lat > 90 || *lon < -180 || *lon > 180) return NO;
    _locationName = [loc[@"name"] isKindOfClass:[NSString class]] ? loc[@"name"] : @"?";
    return YES;
}

- (void)refreshNow {
    if (!_started || _debugOverride || _inFlight) return;
    if (!_pm.weatherAutoTheme) { [self scheduleNext]; return; }

    double lat, lon;
    if (![self loadLocationLatitude:&lat longitude:&lon]) {
        NSLog(@"[Weather] no valid location; create %@ in Documents/AmbientDisplay with "
              @"{\"location\":{\"name\":\"City\",\"latitude\":0.0,\"longitude\":0.0}}", kSettingsFileName);
        [self scheduleNext];
        return;
    }

    _inFlight = YES;
    __weak typeof(self) weakSelf = self;
    [_service fetchConditionsForLatitude:lat longitude:lon
                              completion:^(AmbientWeatherConditions *conditions, NSError *error) {
        typeof(self) s = weakSelf;
        if (!s) return;
        s->_inFlight = NO;
        if (conditions && !s->_debugOverride && s->_pm.weatherAutoTheme) {
            [s evaluateConditions:conditions];
        } else if (!conditions) {
            NSLog(@"[Weather] fetch failed, keeping current theme: %@", error);   // silent skip
        }
        [s scheduleNext];
    }];
}

#pragma mark Decision

- (void)evaluateConditions:(AmbientWeatherConditions *)conditions {
    _lastConditions = conditions;
    NSArray<NSString *> *candidates = [AmbientWeatherTags candidateTagsForWMOCode:conditions.wmoCode
                                                                          isDay:conditions.isDay];
    NSLog(@"[Weather] %@ (%@) -> candidates %@", conditions, _locationName ?: @"?", candidates);
    [self applyCandidates:candidates];
}

/// Walk tiers best-first; the first tier that has any matching theme decides.
/// If the active theme is already in that tier, leave it alone (no re-roll).
- (void)applyCandidates:(NSArray<NSString *> *)candidates {
    AmbientTheme *current = _pm.activeTheme;
    for (NSString *tag in candidates) {
        NSMutableArray<AmbientTheme *> *matches = [NSMutableArray array];
        for (AmbientTheme *theme in _pm.installedThemes) {
            if ([theme.weatherTags containsObject:tag]) [matches addObject:theme];
        }
        if (matches.count == 0) continue;

        if (current && [current.weatherTags containsObject:tag]) {
            NSLog(@"[Weather] '%@' already matches current theme, keeping", tag);
            return;
        }
        AmbientTheme *pick = matches[arc4random_uniform((uint32_t)matches.count)];
        NSError *error = nil;
        if ([_pm setActiveThemeId:pick.themeId error:&error]) {
            NSLog(@"[Weather] '%@' -> switched to %@", tag, pick.themeId);
        } else {
            NSLog(@"[Weather] switch to %@ failed: %@", pick.themeId, error);
        }
        return;
    }
    NSLog(@"[Weather] no theme matches %@, keeping current", candidates);
}

#pragma mark Test hook

- (void)debugApplyTag:(NSString *)tag {
    _debugOverride = YES;
    [self applyCandidates:@[tag.lowercaseString]];
}

@end
