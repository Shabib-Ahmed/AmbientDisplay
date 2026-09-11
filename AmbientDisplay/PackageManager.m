#import "PackageManager.h"

NSString * const PackageManagerErrorDomain = @"PackageManagerErrorDomain";

static NSString * const kAmbientDisplayDirName = @"AmbientDisplay";
static NSString * const kPackagesDirName = @"Packages";
static NSString * const kStateFileName = @"state.json";
static NSString * const kThemeDirName = @"Theme";
static NSString * const kPlaylistDirName = @"Playlist";
static NSString * const kManifestFileName = @"manifest.json";

// Each package's manifest.json declares exactly one of these under the
// "type" key. Themes and playlists are fully independent packages now —
// a package is never both.
static NSString * const kPackageTypeTheme = @"theme";
static NSString * const kPackageTypePlaylist = @"playlist";

#pragma mark - AmbientThemeLayer

// A layer is deliberately opaque beyond its "kind" - PackageManager has no
// knowledge of what fields a given kind requires (a "particles" effect
// might have "texture"/"count"/"speed"; a "clock" layer might have
// "format"/"position"; a "custom" effect just points at a recipe file).
// That interpretation belongs entirely to whatever renders each kind.
// This keeps adding a new effect/layer kind a renderer-only change - no
// PackageManager or manifest-schema change required.
@interface AmbientThemeLayer ()
- (instancetype)initWithKind:(NSString *)kind
                    parameters:(NSDictionary<NSString *, id> *)parameters;
@end

@implementation AmbientThemeLayer

- (instancetype)initWithKind:(NSString *)kind
                    parameters:(NSDictionary<NSString *, id> *)parameters {
    self = [super init];
    if (self) {
        _kind = [kind copy];
        _parameters = [parameters copy];
    }
    return self;
}

@end

#pragma mark - AmbientTheme

@interface AmbientTheme ()
- (instancetype)initWithThemeId:(NSString *)themeId
                       packageId:(NSString *)packageId
                     displayName:(NSString *)displayName
               backgroundVideoURL:(NSURL *)backgroundVideoURL
                themeDirectoryURL:(NSURL *)themeDirectoryURL
                          layers:(NSArray<AmbientThemeLayer *> *)layers
                     weatherTags:(NSArray<NSString *> *)weatherTags;
@end

@implementation AmbientTheme

- (instancetype)initWithThemeId:(NSString *)themeId
                       packageId:(NSString *)packageId
                     displayName:(NSString *)displayName
               backgroundVideoURL:(NSURL *)backgroundVideoURL
                themeDirectoryURL:(NSURL *)themeDirectoryURL
                          layers:(NSArray<AmbientThemeLayer *> *)layers
                     weatherTags:(NSArray<NSString *> *)weatherTags {
    self = [super init];
    if (self) {
        _themeId = [themeId copy];
        _packageId = [packageId copy];
        _displayName = [displayName copy];
        _backgroundVideoURL = [backgroundVideoURL copy];
        _themeDirectoryURL = [themeDirectoryURL copy];
        _layers = [layers copy];
        _weatherTags = [weatherTags copy];
    }
    return self;
}

@end

#pragma mark - AmbientPlaylist

@interface AmbientPlaylist ()
- (instancetype)initWithPlaylistId:(NSString *)playlistId
                          packageId:(NSString *)packageId
                          trackURLs:(NSArray<NSURL *> *)trackURLs;
@end

@implementation AmbientPlaylist

- (instancetype)initWithPlaylistId:(NSString *)playlistId
                          packageId:(NSString *)packageId
                          trackURLs:(NSArray<NSURL *> *)trackURLs {
    self = [super init];
    if (self) {
        _playlistId = [playlistId copy];
        _packageId = [packageId copy];
        _trackURLs = [trackURLs copy];
    }
    return self;
}

@end

#pragma mark - PackageManager

@interface PackageManager ()
@property (nonatomic, copy) NSString *basePath;
@property (nonatomic, copy) NSArray<AmbientTheme *> *installedThemes;
@property (nonatomic, copy) NSArray<AmbientPlaylist *> *installedPlaylists;
@property (nonatomic, copy, nullable) NSString *activeThemeId;
@property (nonatomic, copy, nullable) NSString *activePlaylistId;
@end

@implementation PackageManager

+ (instancetype)sharedManager {
    static PackageManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *documentsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        NSString *basePath = [documentsPath stringByAppendingPathComponent:kAmbientDisplayDirName];
        instance = [[PackageManager alloc] initWithBaseDirectoryPath:basePath];
    });
    return instance;
}

- (instancetype)initWithBaseDirectoryPath:(NSString *)basePath {
    self = [super init];
    if (self) {
        _basePath = [basePath copy];
        _installedThemes = @[];
        _installedPlaylists = @[];
        _weatherAutoTheme = NO;
    }
    return self;
}

#pragma mark Paths

- (NSString *)packagesDirPath {
    return [self.basePath stringByAppendingPathComponent:kPackagesDirName];
}

- (NSString *)stateFilePath {
    return [self.basePath stringByAppendingPathComponent:kStateFileName];
}

- (void)ensurePackagesDirectoryExists {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [self packagesDirPath];
    BOOL isDir;
    BOOL exists = [fm fileExistsAtPath:path isDirectory:&isDir];
    if (!exists) {
        NSError *error = nil;
        BOOL created = [fm createDirectoryAtPath:path
                      withIntermediateDirectories:YES
                                       attributes:nil
                                            error:&error];
        NSLog(@"[PackageManager] created Packages dir: %d error: %@", created, error);
    }
}

#pragma mark Reload

- (void)reloadInstalledPackages {
    [self ensurePackagesDirectoryExists];
    [self loadState];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *listError = nil;
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:[self packagesDirPath] error:&listError];
    if (listError) {
        NSLog(@"[PackageManager] failed to list Packages dir: %@", listError);
        entries = @[];
    }

    NSMutableArray<AmbientTheme *> *themes = [NSMutableArray array];
    NSMutableArray<AmbientPlaylist *> *playlists = [NSMutableArray array];

    for (NSString *entry in entries) {
        NSString *packageDirPath = [[self packagesDirPath] stringByAppendingPathComponent:entry];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:packageDirPath isDirectory:&isDir] || !isDir) {
            continue;
        }
        [self parsePackageAtPath:packageDirPath intoThemes:themes playlists:playlists];
    }

    self.installedThemes = [themes copy];
    self.installedPlaylists = [playlists copy];

    NSLog(@"[PackageManager] reloaded: %lu themes, %lu playlists",
          (unsigned long)self.installedThemes.count, (unsigned long)self.installedPlaylists.count);
}

- (void)parsePackageAtPath:(NSString *)packageDirPath
                 intoThemes:(NSMutableArray<AmbientTheme *> *)themes
                  playlists:(NSMutableArray<AmbientPlaylist *> *)playlists {
    NSString *manifestPath = [packageDirPath stringByAppendingPathComponent:kManifestFileName];

    NSData *data = [NSData dataWithContentsOfFile:manifestPath];
    if (!data) {
        NSLog(@"[PackageManager] no manifest.json at %@, skipping", packageDirPath);
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![manifest isKindOfClass:[NSDictionary class]] || jsonError) {
        NSLog(@"[PackageManager] malformed manifest.json at %@: %@", packageDirPath, jsonError);
        return;
    }

    NSString *packageId = manifest[@"packageId"];
    if (![packageId isKindOfClass:[NSString class]] || packageId.length == 0) {
        NSLog(@"[PackageManager] manifest at %@ missing packageId, skipping", packageDirPath);
        return;
    }

    NSString *packageType = manifest[@"type"];
    if (![packageType isKindOfClass:[NSString class]]) {
        NSLog(@"[PackageManager] manifest at %@ missing \"type\", skipping", packageDirPath);
        return;
    }

    if ([packageType isEqualToString:kPackageTypeTheme]) {
        NSDictionary *themeDict = manifest[@"theme"];
        if (![themeDict isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[PackageManager] package %@ declares type=theme but has no \"theme\" section, skipping", packageId);
            return;
        }
        AmbientTheme *theme = [self themeFromDict:themeDict packageId:packageId packageDirPath:packageDirPath];
        if (theme) {
            [themes addObject:theme];
        }
    } else if ([packageType isEqualToString:kPackageTypePlaylist]) {
        NSDictionary *playlistDict = manifest[@"playlist"];
        if (![playlistDict isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[PackageManager] package %@ declares type=playlist but has no \"playlist\" section, skipping", packageId);
            return;
        }
        AmbientPlaylist *playlist = [self playlistFromDict:playlistDict packageId:packageId packageDirPath:packageDirPath];
        if (playlist) {
            [playlists addObject:playlist];
        }
    } else {
        NSLog(@"[PackageManager] package %@ has unknown type \"%@\", skipping", packageId, packageType);
        return;
    }
}

- (nullable AmbientTheme *)themeFromDict:(NSDictionary *)dict
                                packageId:(NSString *)packageId
                           packageDirPath:(NSString *)packageDirPath {
    NSDictionary *backgroundDict = dict[@"background"];
    if (![backgroundDict isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[PackageManager] theme in %@ missing \"background\", skipping", packageId);
        return nil;
    }

    NSString *videoFileName = backgroundDict[@"video"];
    if (![videoFileName isKindOfClass:[NSString class]] || videoFileName.length == 0) {
        NSLog(@"[PackageManager] theme in %@ missing background.video, skipping", packageId);
        return nil;
    }

    NSString *themeDirPath = [packageDirPath stringByAppendingPathComponent:kThemeDirName];
    NSString *videoPath = [themeDirPath stringByAppendingPathComponent:videoFileName];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:videoPath]) {
        NSLog(@"[PackageManager] theme background video missing on disk: %@", videoPath);
        return nil;
    }

    NSArray<AmbientThemeLayer *> *layers = [self layersFromArray:dict[@"layers"] packageId:packageId];

    NSArray *rawTags = dict[@"weatherTags"];
    NSMutableArray<NSString *> *weatherTags = [NSMutableArray array];
    if ([rawTags isKindOfClass:[NSArray class]]) {
        for (id tag in rawTags) {
            if ([tag isKindOfClass:[NSString class]]) {
                [weatherTags addObject:[(NSString *)tag lowercaseString]];
            }
        }
    }

    NSString *displayName = dict[@"displayName"];
    if (![displayName isKindOfClass:[NSString class]]) {
        displayName = packageId;
    }

    return [[AmbientTheme alloc] initWithThemeId:[packageId stringByAppendingString:@".theme"]
                                        packageId:packageId
                                      displayName:displayName
                              backgroundVideoURL:[NSURL fileURLWithPath:videoPath]
                               themeDirectoryURL:[NSURL fileURLWithPath:themeDirPath isDirectory:YES]
                                           layers:layers
                                      weatherTags:[weatherTags copy]];
}

// Generic, forward-compatible pass-through: each entry just needs a
// non-empty "kind" string. Everything else in the entry is carried through
// verbatim as that layer's parameters - PackageManager never inspects
// kind-specific fields, so a manifest referencing a kind this build
// doesn't know how to render is skipped (logged) here rather than failing
// the whole theme, and a brand new kind never requires a PackageManager
// change to parse.
- (NSArray<AmbientThemeLayer *> *)layersFromArray:(id)rawLayers packageId:(NSString *)packageId {
    if (![rawLayers isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<AmbientThemeLayer *> *layers = [NSMutableArray array];
    for (id entry in (NSArray *)rawLayers) {
        if (![entry isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[PackageManager] theme in %@ has a non-object layer entry, skipping it", packageId);
            continue;
        }
        NSDictionary *layerDict = (NSDictionary *)entry;
        NSString *kind = layerDict[@"kind"];
        if (![kind isKindOfClass:[NSString class]] || kind.length == 0) {
            NSLog(@"[PackageManager] theme in %@ has a layer with no \"kind\", skipping it", packageId);
            continue;
        }
        [layers addObject:[[AmbientThemeLayer alloc] initWithKind:kind parameters:layerDict]];
    }
    return [layers copy];
}

- (nullable AmbientPlaylist *)playlistFromDict:(NSDictionary *)dict
                                      packageId:(NSString *)packageId
                                 packageDirPath:(NSString *)packageDirPath {
    NSArray *rawTracks = dict[@"tracks"];
    if (![rawTracks isKindOfClass:[NSArray class]] || rawTracks.count == 0) {
        NSLog(@"[PackageManager] playlist in %@ has no tracks, skipping", packageId);
        return nil;
    }

    NSString *playlistDirPath = [packageDirPath stringByAppendingPathComponent:kPlaylistDirName];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSMutableArray<NSURL *> *trackURLs = [NSMutableArray array];
    for (id fileName in rawTracks) {
        if (![fileName isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *trackPath = [playlistDirPath stringByAppendingPathComponent:fileName];
        if (![fm fileExistsAtPath:trackPath]) {
            NSLog(@"[PackageManager] playlist track missing on disk: %@", trackPath);
            continue;
        }
        [trackURLs addObject:[NSURL fileURLWithPath:trackPath]];
    }

    if (trackURLs.count == 0) {
        NSLog(@"[PackageManager] playlist in %@ had zero valid tracks, skipping", packageId);
        return nil;
    }

    return [[AmbientPlaylist alloc] initWithPlaylistId:[packageId stringByAppendingString:@".playlist"]
                                              packageId:packageId
                                              trackURLs:[trackURLs copy]];
}

#pragma mark Lookup

- (nullable AmbientTheme *)themeWithId:(NSString *)themeId {
    for (AmbientTheme *theme in self.installedThemes) {
        if ([theme.themeId isEqualToString:themeId]) {
            return theme;
        }
    }
    return nil;
}

- (nullable AmbientPlaylist *)playlistWithId:(NSString *)playlistId {
    for (AmbientPlaylist *playlist in self.installedPlaylists) {
        if ([playlist.playlistId isEqualToString:playlistId]) {
            return playlist;
        }
    }
    return nil;
}

#pragma mark Selection

- (BOOL)setActiveThemeId:(NSString *)themeId error:(NSError **)error {
    AmbientTheme *theme = [self themeWithId:themeId];
    if (!theme) {
        if (error) {
            *error = [NSError errorWithDomain:PackageManagerErrorDomain
                                          code:PackageManagerErrorUnknownTheme
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"No installed theme with id %@", themeId]}];
        }
        return NO;
    }

    self.activeThemeId = themeId;
    [self saveState];
    return YES;
}

- (BOOL)setActivePlaylistId:(NSString *)playlistId error:(NSError **)error {
    AmbientPlaylist *playlist = [self playlistWithId:playlistId];
    if (!playlist) {
        if (error) {
            *error = [NSError errorWithDomain:PackageManagerErrorDomain
                                          code:PackageManagerErrorUnknownPlaylist
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                     [NSString stringWithFormat:@"No installed playlist with id %@", playlistId]}];
        }
        return NO;
    }

    self.activePlaylistId = playlistId;
    [self saveState];
    return YES;
}

- (nullable AmbientTheme *)randomThemeMatchingWeatherTag:(NSString *)weatherTag {
    NSString *needle = [weatherTag lowercaseString];
    NSMutableArray<AmbientTheme *> *matches = [NSMutableArray array];
    for (AmbientTheme *theme in self.installedThemes) {
        if ([theme.weatherTags containsObject:needle]) {
            [matches addObject:theme];
        }
    }
    if (matches.count == 0) {
        return nil;
    }
    NSUInteger index = arc4random_uniform((uint32_t)matches.count);
    return matches[index];
}

#pragma mark Resolved active items

- (nullable AmbientTheme *)activeTheme {
    return self.activeThemeId ? [self themeWithId:self.activeThemeId] : nil;
}

- (nullable AmbientPlaylist *)activePlaylist {
    return self.activePlaylistId ? [self playlistWithId:self.activePlaylistId] : nil;
}

#pragma mark Resolution

- (nullable AmbientTheme *)resolveActiveThemeWithFallback {
    AmbientTheme *theme = self.activeTheme;
    if (theme) {
        return theme;
    }

    AmbientTheme *fallback = self.installedThemes.firstObject;
    if (!fallback) {
        NSLog(@"[PackageManager] No themes installed");
        return nil;
    }

    NSError *error = nil;
    if (![self setActiveThemeId:fallback.themeId error:&error]) {
        NSLog(@"[PackageManager] failed to activate fallback theme: %@", error);
        return nil;
    }
    // No recursive re-resolve here: we just activated `fallback` directly,
    // so `self.activeTheme` is now guaranteed to return it.
    return fallback;
}

- (nullable AmbientPlaylist *)resolveActivePlaylistWithFallback {
    AmbientPlaylist *playlist = self.activePlaylist;
    if (playlist) {
        return playlist;
    }

    // Nothing explicitly chosen (independent of theme selection now) - default
    // to the first installed playlist so music plays out of the box. Stay
    // silent only when there's genuinely no playlist package installed.
    AmbientPlaylist *fallback = self.installedPlaylists.firstObject;
    if (!fallback) {
        NSLog(@"[PackageManager] No playlists installed");
        return nil;
    }

    NSError *error = nil;
    if (![self setActivePlaylistId:fallback.playlistId error:&error]) {
        NSLog(@"[PackageManager] failed to activate fallback playlist: %@", error);
        return nil;
    }
    return fallback;
}

#pragma mark Settings persistence

- (void)setWeatherAutoTheme:(BOOL)weatherAutoTheme {
    _weatherAutoTheme = weatherAutoTheme;
    [self saveState];
}

#pragma mark State file

- (void)loadState {
    NSData *data = [NSData dataWithContentsOfFile:[self stateFilePath]];
    if (!data) {
        NSLog(@"[PackageManager] no state.json yet, using defaults");
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *state = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![state isKindOfClass:[NSDictionary class]] || jsonError) {
        NSLog(@"[PackageManager] malformed state.json: %@", jsonError);
        return;
    }

    if ([state[@"activeThemeId"] isKindOfClass:[NSString class]]) {
        self.activeThemeId = state[@"activeThemeId"];
    }
    if ([state[@"activePlaylistId"] isKindOfClass:[NSString class]]) {
        self.activePlaylistId = state[@"activePlaylistId"];
    }

    NSDictionary *settings = state[@"settings"];
    if ([settings isKindOfClass:[NSDictionary class]]) {
        if (settings[@"weatherAutoTheme"]) {
            _weatherAutoTheme = [settings[@"weatherAutoTheme"] boolValue];
        }
    }
}

- (void)saveState {
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    if (self.activeThemeId) {
        state[@"activeThemeId"] = self.activeThemeId;
    }
    if (self.activePlaylistId) {
        state[@"activePlaylistId"] = self.activePlaylistId;
    }
    state[@"settings"] = @{
        @"weatherAutoTheme": @(self.weatherAutoTheme),
    };

    NSError *jsonError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:&jsonError];
    if (!data) {
        NSLog(@"[PackageManager] failed to serialize state.json: %@", jsonError);
        return;
    }

    NSError *writeError = nil;
    BOOL wrote = [data writeToFile:[self stateFilePath] options:NSDataWritingAtomic error:&writeError];
    NSLog(@"[PackageManager] saveState wrote=%d error=%@", wrote, writeError);
}

@end
