#import "AmbientShaderRecipe.h"
#import "PackageManager.h"
#import "AmbientShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

@implementation AmbientShaderPass

- (instancetype)initWithShaderPath:(NSString *)shaderPath
                             params:(NSDictionary<NSString *, id> *)params
                             inputs:(nullable NSArray<NSString *> *)inputs {
    if ((self = [super init])) {
        _shaderPath = [shaderPath copy];
        _params = [params copy];
        _inputs = [inputs copy];
    }
    return self;
}

@end

@implementation AmbientShaderRecipe

- (instancetype)initWithPasses:(NSArray<AmbientShaderPass *> *)passes {
    if ((self = [super init])) {
        _passes = [passes copy];
    }
    return self;
}

@end

@implementation AmbientShaderRecipeLoader

+ (nullable AmbientShaderRecipe *)recipeForThemeLayer:(AmbientThemeLayer *)themeLayer
                                      themeDirectoryURL:(NSURL *)themeDirectoryURL {
    id rawShaders = themeLayer.parameters[@"shaders"];
    if (![rawShaders isKindOfClass:[NSArray class]] || [(NSArray *)rawShaders count] == 0) {
        NSLog(@"[AmbientShaderRecipeLoader] effect layer has no \"shaders\" array, skipping");
        return nil;
    }
    NSArray *rawPasses = (NSArray *)rawShaders;

    if (rawPasses.count > AmbientShaderMaxPassCount) {
        NSLog(@"[AmbientShaderRecipeLoader] effect layer has %lu passes, exceeds max of %d, skipping",
              (unsigned long)rawPasses.count, AmbientShaderMaxPassCount);
        return nil;
    }

    NSMutableArray<AmbientShaderPass *> *passes = [NSMutableArray arrayWithCapacity:rawPasses.count];

    for (id rawPass in rawPasses) {
        if (![rawPass isKindOfClass:[NSDictionary class]]) {
            NSLog(@"[AmbientShaderRecipeLoader] non-object entry in \"shaders\", skipping layer");
            return nil;
        }
        NSDictionary *passDict = (NSDictionary *)rawPass;

        NSString *path = passDict[@"path"];
        if (![path isKindOfClass:[NSString class]] || path.length == 0) {
            NSLog(@"[AmbientShaderRecipeLoader] shader pass missing \"path\", skipping layer");
            return nil;
        }

        NSDictionary *params = @{};
        if ([passDict[@"params"] isKindOfClass:[NSDictionary class]]) {
            params = passDict[@"params"];
        } else if (passDict[@"params"] != nil) {
            NSLog(@"[AmbientShaderRecipeLoader] shader pass \"params\" is not an object, ignoring it (path=%@)", path);
        }

        NSArray<NSString *> *inputs = nil;
        if ([passDict[@"inputs"] isKindOfClass:[NSArray class]]) {
            NSMutableArray<NSString *> *validated = [NSMutableArray array];
            for (id inputName in (NSArray *)passDict[@"inputs"]) {
                if ([inputName isKindOfClass:[NSString class]]) {
                    [validated addObject:inputName];
                } else {
                    NSLog(@"[AmbientShaderRecipeLoader] non-string entry in \"inputs\", ignoring it (path=%@)", path);
                }
            }
            inputs = [validated copy];
        } else if (passDict[@"inputs"] != nil) {
            NSLog(@"[AmbientShaderRecipeLoader] shader pass \"inputs\" is not an array, ignoring it (path=%@)", path);
        }

        [passes addObject:[[AmbientShaderPass alloc] initWithShaderPath:path params:params inputs:inputs]];
    }

    if (passes.count == 0) {
        NSLog(@"[AmbientShaderRecipeLoader] no valid shader passes parsed, skipping layer");
        return nil;
    }

    return [[AmbientShaderRecipe alloc] initWithPasses:[passes copy]];
}

@end

NS_ASSUME_NONNULL_END
