#import "AmbientShaderLibraryCache.h"
// No header import needed for the vertex function itself - the caller
// (AmbientShaderEffectRenderer) is responsible for loading the app's
// default MTLLibrary (containing ambient_fullscreen_vertex, compiled
// from Rendering/Shaders/AmbientShaderCommon.metal) and passing it in
// via -initWithDevice:vertexLibrary:themeDirectoryURL:pixelFormat:.

NS_ASSUME_NONNULL_BEGIN

static NSString * const kVertexFunctionName = @"ambient_fullscreen_vertex";

// Package .metal source is compiled standalone at runtime from its own
// file content alone (read as a plain NSString below) - there's no
// build-system-level #include resolution available for a package's
// sibling files the way AmbientShaderCommon.metal gets one at app-build
// time. So every package fragment shader needs AmbientShaderUniforms,
// VertexOut, and the binding-index constants available without
// redeclaring them by hand in every package file (error-prone, and the
// whole point of AmbientShaderTypes.h was one source of truth). This
// prelude is prepended to package source before compilation to provide
// exactly that.
//
// TODO: this is now a THIRD hand-maintained copy of AmbientShaderUniforms
// (alongside AmbientShaderTypes.h and, via #include, AmbientShaderCommon.metal)
// plus the only copy of VertexOut outside AmbientShaderCommon.metal itself -
// nothing enforces these stay in sync. Also includes a small set of
// color/noise helpers (ambient_hsv2rgb) that are generically useful
// enough to offer every package shader rather than have each one
// hand-roll its own.
static NSString * const kPackageShaderPrelude =
    @"#include <metal_stdlib>\n"
    @"using namespace metal;\n"
    @"\n"
    @"struct AmbientShaderUniforms {\n"
    @"    float time;\n"
    @"    float2 resolution;\n"
    @"    float4 params;\n"
    @"    float sensitivity;\n"
    @"};\n"
    @"\n"
    @"struct VertexOut {\n"
    @"    float4 position [[position]];\n"
    @"    float2 uv;\n"
    @"};\n"
    @"\n"
    @"#define AmbientShaderUniformBufferIndex 0\n"
    @"#define AmbientShaderTexturePreviousIndex 0\n"
    @"#define AmbientShaderTextureOriginalIndex 1\n"
    @"#define AmbientShaderTextureAudioLevelsIndex 2\n"
    @"#define AmbientShaderTextureSourceVideoIndex 3\n"
    @"\n"
    @"// HSV (0...1 each channel) -> linear RGB. Standard compact form.\n"
    @"static float3 ambient_hsv2rgb(float3 hsv) {\n"
    @"    float3 rgb = clamp(abs(fmod(hsv.x * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);\n"
    @"    rgb = rgb * rgb * (3.0 - 2.0 * rgb);\n"
    @"    return hsv.z * mix(float3(1.0), rgb, hsv.y);\n"
    @"}\n"
    @"\n";

// Shader source is a handful of lines of GPU code, not a media asset -
// this cap exists purely to reject a pathological/malformed file before
// handing it to the Metal compiler, same posture as AmbientTextureCache's
// file-size cap for images.
static const unsigned long long kMaxShaderSourceSizeBytes = 512 * 1024; // 512 KB

@interface AmbientShaderLibraryCache ()
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLLibrary> vertexLibrary;
@property (nonatomic, copy) NSURL *themeDirectoryURL;
@property (nonatomic, copy) NSURL *resolvedThemeDirectoryURL; // standardized, for containment checks
@property (nonatomic, assign) MTLPixelFormat pixelFormat;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id<MTLRenderPipelineState>> *pipelineCache;
@end

@implementation AmbientShaderLibraryCache

- (instancetype)initWithDevice:(id<MTLDevice>)device
                 vertexLibrary:(id<MTLLibrary>)vertexLibrary
             themeDirectoryURL:(NSURL *)themeDirectoryURL
                   pixelFormat:(MTLPixelFormat)pixelFormat {
    if ((self = [super init])) {
        _device = device;
        _vertexLibrary = vertexLibrary;
        _themeDirectoryURL = [themeDirectoryURL copy];
        _resolvedThemeDirectoryURL = [themeDirectoryURL URLByStandardizingPath];
        _pixelFormat = pixelFormat;
        _pipelineCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (nullable id<MTLRenderPipelineState>)pipelineStateForShaderPath:(NSString *)shaderPath {
    id<MTLRenderPipelineState> cached = self.pipelineCache[shaderPath];
    if (cached) {
        return cached;
    }

    NSURL *resolvedURL = [self resolvedURLForRelativePath:shaderPath];
    if (!resolvedURL) {
        return nil;
    }

    NSString *extension = resolvedURL.pathExtension.lowercaseString;
    id<MTLLibrary> compiledLibrary = nil;

    if ([extension isEqualToString:@"metal"]) {
        compiledLibrary = [self compileSourceLibraryAtURL:resolvedURL shaderPath:shaderPath];
    } else if ([extension isEqualToString:@"metallib"]) {
        NSError *loadError = nil;
        compiledLibrary = [self.device newLibraryWithFile:resolvedURL.path error:&loadError];
        if (!compiledLibrary) {
            NSLog(@"[AmbientShaderLibraryCache] failed to load metallib %@: %@", shaderPath, loadError);
            return nil;
        }
    } else {
        NSLog(@"[AmbientShaderLibraryCache] unsupported shader file extension '%@' for %@", extension, shaderPath);
        return nil;
    }

    if (!compiledLibrary) {
        return nil;
    }

    NSString *fragmentFunctionName = [self fragmentFunctionNameForShaderPath:shaderPath];
    id<MTLFunction> fragmentFunction = [compiledLibrary newFunctionWithName:fragmentFunctionName];
    if (!fragmentFunction) {
        NSLog(@"[AmbientShaderLibraryCache] %@ does not define expected fragment function '%@'",
              shaderPath, fragmentFunctionName);
        return nil;
    }

    id<MTLFunction> vertexFunction = [self.vertexLibrary newFunctionWithName:kVertexFunctionName];
    if (!vertexFunction) {
        NSLog(@"[AmbientShaderLibraryCache] app-bundled vertex function '%@' not found - "
              @"is AmbientShaderCommon.metal in the target's compile sources?", kVertexFunctionName);
        return nil;
    }

    MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = vertexFunction;
    descriptor.fragmentFunction = fragmentFunction;
    descriptor.colorAttachments[0].pixelFormat = self.pixelFormat;
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    NSError *pipelineError = nil;
    id<MTLRenderPipelineState> pipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor
                                                                                              error:&pipelineError];
    if (!pipelineState) {
        NSLog(@"[AmbientShaderLibraryCache] failed to build pipeline state for %@: %@", shaderPath, pipelineError);
        return nil;
    }

    self.pipelineCache[shaderPath] = pipelineState;
    return pipelineState;
}

#pragma mark - Compilation

- (nullable id<MTLLibrary>)compileSourceLibraryAtURL:(NSURL *)resolvedURL shaderPath:(NSString *)shaderPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *attrError = nil;
    NSDictionary<NSFileAttributeKey, id> *attrs = [fm attributesOfItemAtPath:resolvedURL.path error:&attrError];
    if (!attrs) {
        NSLog(@"[AmbientShaderLibraryCache] shader not found on disk: %@ (%@)", shaderPath, attrError);
        return nil;
    }
    unsigned long long fileSize = attrs.fileSize;
    if (fileSize == 0 || fileSize > kMaxShaderSourceSizeBytes) {
        NSLog(@"[AmbientShaderLibraryCache] shader %@ rejected: size %llu bytes exceeds cap", shaderPath, fileSize);
        return nil;
    }

    NSError *readError = nil;
    NSString *fileSource = [NSString stringWithContentsOfURL:resolvedURL encoding:NSUTF8StringEncoding error:&readError];
    if (!fileSource) {
        NSLog(@"[AmbientShaderLibraryCache] failed to read shader source %@: %@", shaderPath, readError);
        return nil;
    }
    NSString *source = [kPackageShaderPrelude stringByAppendingString:fileSource];

    // Synchronous compile - theme switches aren't hot-path/high-frequency
    // enough to justify the async variant + completion-handler plumbing
    // right now. Revisit if theme-switch stutter is ever observed.
    NSError *compileError = nil;
    id<MTLLibrary> library = [self.device newLibraryWithSource:source options:nil error:&compileError];
    if (!library) {
        NSLog(@"[AmbientShaderLibraryCache] failed to compile shader %@: %@", shaderPath, compileError);
        return nil;
    }
    return library;
}

- (NSString *)fragmentFunctionNameForShaderPath:(NSString *)shaderPath {
    NSString *baseName = shaderPath.lastPathComponent.stringByDeletingPathExtension;
    return [NSString stringWithFormat:@"fragment_%@", baseName.lowercaseString];
}

#pragma mark - Path resolution / containment
- (nullable NSURL *)resolvedURLForRelativePath:(NSString *)relativePath {
    if ([relativePath hasPrefix:@"/"]) {
        NSLog(@"[AmbientShaderLibraryCache] rejected absolute path: %@", relativePath);
        return nil;
    }

    NSArray<NSString *> *components = [relativePath componentsSeparatedByString:@"/"];
    if ([components containsObject:@".."]) {
        NSLog(@"[AmbientShaderLibraryCache] rejected path with '..': %@", relativePath);
        return nil;
    }

    NSURL *candidate = [self.themeDirectoryURL URLByAppendingPathComponent:relativePath];
    NSURL *resolvedCandidate = [candidate URLByStandardizingPath];

    NSString *resolvedThemeDirPath = self.resolvedThemeDirectoryURL.path;
    if (![resolvedThemeDirPath hasSuffix:@"/"]) {
        resolvedThemeDirPath = [resolvedThemeDirPath stringByAppendingString:@"/"];
    }

    if (![resolvedCandidate.path hasPrefix:resolvedThemeDirPath]) {
        NSLog(@"[AmbientShaderLibraryCache] resolved path escapes theme directory: %@", relativePath);
        return nil;
    }

    return resolvedCandidate;
}

@end

NS_ASSUME_NONNULL_END
