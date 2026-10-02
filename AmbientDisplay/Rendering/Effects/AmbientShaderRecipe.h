#import <Foundation/Foundation.h>

@class AmbientThemeLayer;

NS_ASSUME_NONNULL_BEGIN


@interface AmbientShaderPass : NSObject


@property (nonatomic, copy, readonly) NSString *shaderPath;

@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *params;

@property (nonatomic, copy, readonly, nullable) NSArray<NSString *> *inputs;

- (instancetype)initWithShaderPath:(NSString *)shaderPath
                             params:(NSDictionary<NSString *, id> *)params
                             inputs:(nullable NSArray<NSString *> *)inputs NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface AmbientShaderRecipe : NSObject

@property (nonatomic, copy, readonly) NSArray<AmbientShaderPass *> *passes;

- (instancetype)initWithPasses:(NSArray<AmbientShaderPass *> *)passes NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface AmbientShaderRecipeLoader : NSObject

+ (nullable AmbientShaderRecipe *)recipeForThemeLayer:(AmbientThemeLayer *)themeLayer
                                      themeDirectoryURL:(NSURL *)themeDirectoryURL;

@end

NS_ASSUME_NONNULL_END
