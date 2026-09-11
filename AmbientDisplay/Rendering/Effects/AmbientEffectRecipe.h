#import <Foundation/Foundation.h>

@class AmbientThemeLayer;

NS_ASSUME_NONNULL_BEGIN

// The fixed, closed set of drawing primitives a recipe can be built from.
// This is intentionally not extensible via data - adding a new primitive
// type is a code change (a new case here, a new case in the renderer),
// which is exactly the point: recipes describe compositions of these
// primitives, they never carry code of their own. Any expressiveness a
// third-party "custom" recipe has comes from combining/parameterizing
// this fixed vocabulary, not from anything Turing-complete.
typedef NS_ENUM(NSInteger, AmbientEffectPrimitiveType) {
    AmbientEffectPrimitiveTypeParticleEmitter,
    AmbientEffectPrimitiveTypeGradientWash,
    AmbientEffectPrimitiveTypeRadialPulse,
    AmbientEffectPrimitiveTypeSpriteAnimation,
};

// One primitive within a recipe. By the time this object exists its
// parameters have already been validated and range-clamped by
// AmbientEffectRecipeLoader - a renderer consuming an AmbientEffectPrimitive
// should never need to defend against a bogus value.
@interface AmbientEffectPrimitive : NSObject

@property (nonatomic, assign, readonly) AmbientEffectPrimitiveType primitiveType;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *parameters;

@end

// An ordered stack of primitives that together make up one effect layer.
// Built-in inline effects (e.g. a layer with "type": "particles") produce
// a single-primitive recipe; a "type": "custom" layer loads a recipe file
// that may combine several primitives. Renderers don't need to know or
// care which case they're looking at.
@interface AmbientEffectRecipe : NSObject

@property (nonatomic, copy, readonly) NSArray<AmbientEffectPrimitive *> *primitives;

@end

@interface AmbientEffectRecipeLoader : NSObject

// Builds a recipe from an "effect" kind theme layer. For a recognized
// built-in shorthand ("type": "particles"/"gradientWash"/"radialPulse"/
// "spriteAnimation") this synthesizes a single-primitive recipe directly
// from the layer's own parameters. For "type": "custom" this loads and
// parses the referenced recipe JSON file (path resolved and contained
// within themeDirectoryURL, same rules as AmbientTextureCache). Returns
// nil (logged) for any unrecognized type or malformed/out-of-range
// parameters rather than throwing.
+ (nullable AmbientEffectRecipe *)recipeForThemeLayer:(AmbientThemeLayer *)themeLayer
                                      themeDirectoryURL:(NSURL *)themeDirectoryURL;

@end

NS_ASSUME_NONNULL_END
