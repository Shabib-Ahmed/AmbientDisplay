#import "AmbientShaderEffectRenderer.h"
#import <MetalKit/MetalKit.h>
#import "PackageManager.h"
#import "AmbientShaderRecipe.h"
#import "AmbientShaderLibraryCache.h"
#import "AmbientAudioLevelsTextureProvider.h"
#import "AmbientShaderTypes.h"

NS_ASSUME_NONNULL_BEGIN

static const NSInteger kPreferredFramesPerSecond = 30; // matches old visualizer's display-link rate
static const NSUInteger kAudioLevelsCanonicalWidth = 64;
static const MTLPixelFormat kColorPixelFormat = MTLPixelFormatBGRA8Unorm;

// Reads "x"/"y"/"z"/"w" (each an optional NSNumber, default 0) out of a
// pass's params dict into the fixed-size uniform slot every shader gets.
// See AmbientShaderRecipe.h for why this 4-float convention was chosen.
static vector_float4 AmbientParamsDictToFloat4(NSDictionary<NSString *, id> *params) {
    float x = [params[@"x"] isKindOfClass:[NSNumber class]] ? [(NSNumber *)params[@"x"] floatValue] : 0.0f;
    float y = [params[@"y"] isKindOfClass:[NSNumber class]] ? [(NSNumber *)params[@"y"] floatValue] : 0.0f;
    float z = [params[@"z"] isKindOfClass:[NSNumber class]] ? [(NSNumber *)params[@"z"] floatValue] : 0.0f;
    float w = [params[@"w"] isKindOfClass:[NSNumber class]] ? [(NSNumber *)params[@"w"] floatValue] : 0.0f;
    return (vector_float4){x, y, z, w};
}

@interface AmbientShaderEffectRenderer () <MTKViewDelegate>
@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) AmbientShaderRecipe *recipe;
@property (nonatomic, strong) NSArray<id<MTLRenderPipelineState>> *pipelineStates; // one per pass, index-aligned with recipe.passes
@property (nonatomic, strong, nullable) id<MTLTexture> pingTexture;
@property (nonatomic, strong, nullable) id<MTLTexture> pongTexture;
@property (nonatomic, strong, nullable) AmbientAudioLevelsTextureProvider *audioLevelsProvider; // only if some pass wants it
@property (nonatomic, assign) CFTimeInterval startTime;
@property (nonatomic, assign) float layerSensitivity; // theme layer's "sensitivity" param, passed into every pass's uniforms
@end

@implementation AmbientShaderEffectRenderer

+ (nullable instancetype)rendererWithThemeLayer:(AmbientThemeLayer *)themeLayer
                                          context:(AmbientThemeRenderContext *)context {
    if (![themeLayer.kind isEqualToString:@"effect"]) {
        return nil;
    }

    AmbientShaderRecipe *recipe = [AmbientShaderRecipeLoader recipeForThemeLayer:themeLayer
                                                                themeDirectoryURL:context.themeDirectoryURL];
    if (recipe == nil || recipe.passes.count == 0) {
        // AmbientShaderRecipeLoader already logs the specific reason.
        return nil;
    }
    if (recipe.passes.count > AmbientShaderMaxPassCount) {
        NSLog(@"[AmbientShaderEffectRenderer] recipe has %lu passes, exceeds max of %d, declining layer",
              (unsigned long)recipe.passes.count, AmbientShaderMaxPassCount);
        return nil;
    }

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        NSLog(@"[AmbientShaderEffectRenderer] no Metal device available, declining layer");
        return nil;
    }

    id<MTLLibrary> vertexLibrary = [device newDefaultLibrary];
    if (!vertexLibrary) {
        NSLog(@"[AmbientShaderEffectRenderer] app's default MTLLibrary not found - "
              @"is AmbientShaderCommon.metal in the target's compile sources?");
        return nil;
    }

    AmbientShaderLibraryCache *libraryCache =
        [[AmbientShaderLibraryCache alloc] initWithDevice:device
                                             vertexLibrary:vertexLibrary
                                         themeDirectoryURL:context.themeDirectoryURL
                                               pixelFormat:kColorPixelFormat];

    NSMutableArray<id<MTLRenderPipelineState>> *pipelineStates =
        [NSMutableArray arrayWithCapacity:recipe.passes.count];
    for (AmbientShaderPass *pass in recipe.passes) {
        id<MTLRenderPipelineState> pipelineState = [libraryCache pipelineStateForShaderPath:pass.shaderPath];
        if (!pipelineState) {
            // AmbientShaderLibraryCache already logged the specific reason -
            // a bad shader in one layer shouldn't half-render, so bail on
            // the whole layer rather than skip just this pass.
            return nil;
        }
        [pipelineStates addObject:pipelineState];
    }

    id<MTLCommandQueue> commandQueue = [device newCommandQueue];
    if (!commandQueue) {
        NSLog(@"[AmbientShaderEffectRenderer] failed to create command queue, declining layer");
        return nil;
    }

    BOOL wantsAudioLevels = NO;
    for (AmbientShaderPass *pass in recipe.passes) {
        if ([pass.inputs containsObject:@"audioLevels"]) {
            wantsAudioLevels = YES;
            break;
        }
    }

    float sensitivity = 1.0f;
    if ([themeLayer.parameters[@"sensitivity"] isKindOfClass:[NSNumber class]]) {
        sensitivity = [(NSNumber *)themeLayer.parameters[@"sensitivity"] floatValue];
        sensitivity = MAX(0.0f, MIN(10.0f, sensitivity));
    }

    AmbientAudioLevelsTextureProvider *audioLevelsProvider = nil;
    if (wantsAudioLevels) {
        audioLevelsProvider = [[AmbientAudioLevelsTextureProvider alloc] initWithDevice:device
                                                                            canonicalWidth:kAudioLevelsCanonicalWidth];
        audioLevelsProvider.audioDataSource = context.audioDataSource;
        audioLevelsProvider.sensitivity = sensitivity;
        if (context.audioDataSource == nil) {
            NSLog(@"[AmbientShaderEffectRenderer] layer declares \"audioLevels\" input but context has no "
                  @"audioDataSource - will render with a silent (all-zero) levels texture");
        }
    }

    MTKView *metalView = [[MTKView alloc] initWithFrame:CGRectZero device:device];
    metalView.colorPixelFormat = kColorPixelFormat;
    metalView.preferredFramesPerSecond = kPreferredFramesPerSecond;
    metalView.paused = YES;
    metalView.enableSetNeedsDisplay = NO;
    // Effect layers stack over the background video and any layers
    // below them - both the view and its Metal drawable need to be
    // non-opaque, or CoreAnimation will happily paint over everything
    // beneath this layer with black.
    metalView.opaque = NO;
    metalView.backgroundColor = [UIColor clearColor];
    ((CAMetalLayer *)metalView.layer).opaque = NO;

    AmbientShaderEffectRenderer *renderer = [[AmbientShaderEffectRenderer alloc] init];
    renderer.device = device;
    renderer.commandQueue = commandQueue;
    renderer.recipe = recipe;
    renderer.pipelineStates = [pipelineStates copy];
    renderer.audioLevelsProvider = audioLevelsProvider;
    renderer.layerSensitivity = sensitivity;
    renderer.metalView = metalView;
    metalView.delegate = renderer;

    return renderer;
}

- (UIView *)view {
    return self.metalView;
}

- (void)start {
    self.startTime = CACurrentMediaTime();
    self.metalView.paused = NO;
}

- (void)stop {
    self.metalView.paused = YES;
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.pingTexture = nil;
    self.pongTexture = nil;

    // Single-pass recipes (the common case - e.g. Bars/Waveform) draw
    // straight to the drawable and never touch ping/pong, so don't
    // bother allocating intermediate textures for them.
    if (self.recipe.passes.count <= 1) {
        return;
    }
    if (size.width < 1 || size.height < 1) {
        return;
    }

    MTLTextureDescriptor *descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:kColorPixelFormat
                                                             width:(NSUInteger)size.width
                                                            height:(NSUInteger)size.height
                                                         mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModePrivate;

    self.pingTexture = [self.device newTextureWithDescriptor:descriptor];
    self.pongTexture = [self.device newTextureWithDescriptor:descriptor];
    if (!self.pingTexture || !self.pongTexture) {
        NSLog(@"[AmbientShaderEffectRenderer] failed to allocate %.0fx%.0f ping/pong textures",
              size.width, size.height);
    }
}

- (void)drawInMTKView:(MTKView *)view {
    id<CAMetalDrawable> drawable = view.currentDrawable;
    MTLRenderPassDescriptor *finalPassDescriptor = view.currentRenderPassDescriptor;
    if (!drawable || !finalPassDescriptor) {
        return;
    }

    if (self.audioLevelsProvider) {
        // Once per frame regardless of how many passes read it.
        [self.audioLevelsProvider tick];
    }

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    if (!commandBuffer) {
        return;
    }

    AmbientShaderUniforms uniforms;
    uniforms.time = (float)(CACurrentMediaTime() - self.startTime);
    uniforms.resolution = (vector_float2){(float)view.drawableSize.width, (float)view.drawableSize.height};
    uniforms.sensitivity = self.layerSensitivity;

    NSArray<AmbientShaderPass *> *passes = self.recipe.passes;
    NSUInteger passCount = passes.count;
    id<MTLTexture> previousPassOutput = nil;
    // Alternates ping/pong for every pass except the last, which always
    // targets the drawable.
    BOOL nextIntermediateIsPing = YES;

    for (NSUInteger i = 0; i < passCount; i++) {
        AmbientShaderPass *pass = passes[i];
        BOOL isLastPass = (i == passCount - 1);

        MTLRenderPassDescriptor *passDescriptor;
        id<MTLTexture> thisPassOutput;
        if (isLastPass) {
            passDescriptor = finalPassDescriptor;
            thisPassOutput = nil; // drawable - not sampleable as "previous" by a later pass anyway
        } else {
            thisPassOutput = nextIntermediateIsPing ? self.pingTexture : self.pongTexture;
            if (!thisPassOutput) {
                // Ping/pong not allocated yet (e.g. first frame before a
                // resize callback) - skip this frame rather than crash.
                [commandBuffer commit];
                return;
            }
            passDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
            passDescriptor.colorAttachments[0].texture = thisPassOutput;
            passDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
            passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
            passDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        }
        if (isLastPass) {
            finalPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
            finalPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
        }

        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];
        [encoder setRenderPipelineState:self.pipelineStates[i]];

        uniforms.params = AmbientParamsDictToFloat4(pass.params);
        [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:AmbientShaderUniformBufferIndex];

        for (NSString *inputName in pass.inputs) {
            if ([inputName isEqualToString:@"previous"]) {
                if (previousPassOutput) {
                    [encoder setFragmentTexture:previousPassOutput atIndex:AmbientShaderTexturePreviousIndex];
                }
                // Pass 0 has no "previous" - leaving the slot unbound is
                // expected, not an error.
            } else if ([inputName isEqualToString:@"audioLevels"]) {
                if (self.audioLevelsProvider.texture) {
                    [encoder setFragmentTexture:self.audioLevelsProvider.texture
                                          atIndex:AmbientShaderTextureAudioLevelsIndex];
                }
            } else if ([inputName isEqualToString:@"original"] || [inputName isEqualToString:@"sourceVideo"]) {
                // Reserved slots - see AmbientShaderTypes.h. Not wired up
                // yet, so these inputs are silently left unbound; a
                // shader relying on one of them will just sample an
                // undefined/empty texture until this is implemented.
            }
            // Package-declared named textures: not yet wired up (needs an
            // MTLTexture-returning accessor on AmbientTextureCache) -
            // also silently left unbound for now.
        }

        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [encoder endEncoding];

        previousPassOutput = thisPassOutput;
        nextIntermediateIsPing = !nextIntermediateIsPing;
    }

    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end

NS_ASSUME_NONNULL_END
