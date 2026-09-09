#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AmbientTheme : NSObject

@property (nonatomic, copy, readonly) NSString *themeId;
@property (nonatomic, copy, readonly) NSString *packageId;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, copy, readonly) NSURL *entryPointURL;
@property (nonatomic, copy, readonly) NSURL *readAccessURL;
@property (nonatomic, copy, readonly) NSArray<NSString *> *weatherTags;

@end

@interface AmbientPlaylist : NSObject

@property (nonatomic, copy, readonly) NSString *playlistId;
@property (nonatomic, copy, readonly) NSString *packageId;
@property (nonatomic, copy, readonly) NSArray<NSURL *> *trackURLs;

@end


@interface PackageManager : NSObject

+ (instancetype)sharedManager;
- (instancetype)initWithBaseDirectoryPath:(NSString *)basePath NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;


- (void)reloadInstalledPackages;

@property (nonatomic, copy, readonly) NSArray<AmbientTheme *> *installedThemes;
@property (nonatomic, copy, readonly) NSArray<AmbientPlaylist *> *installedPlaylists;

@property (nonatomic, copy, nullable, readonly) NSString *activeThemeId;
@property (nonatomic, copy, nullable, readonly) NSString *activePlaylistId;

@property (nonatomic, readonly, nullable) AmbientTheme *activeTheme;
@property (nonatomic, readonly, nullable) AmbientPlaylist *activePlaylist;


@property (nonatomic, assign) BOOL syncPlaylistWithTheme;


@property (nonatomic, assign) BOOL weatherAutoTheme;

- (nullable AmbientTheme *)themeWithId:(NSString *)themeId;
- (nullable AmbientPlaylist *)playlistWithId:(NSString *)playlistId;

- (BOOL)setActiveThemeId:(NSString *)themeId error:(NSError **)error;
- (BOOL)setActivePlaylistId:(NSString *)playlistId error:(NSError **)error;

- (nullable AmbientTheme *)randomThemeMatchingWeatherTag:(NSString *)weatherTag;

@end

extern NSString * const PackageManagerErrorDomain;

typedef NS_ENUM(NSInteger, PackageManagerErrorCode) {
    PackageManagerErrorUnknownTheme = 1,
    PackageManagerErrorUnknownPlaylist = 2,
};

NS_ASSUME_NONNULL_END
