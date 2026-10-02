#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface AmbientShaderLibraryCache : NSObject


- (instancetype)initWithDevice:(id<MTLDevice>)device
                 vertexLibrary:(id<MTLLibrary>)vertexLibrary
             themeDirectoryURL:(NSURL *)themeDirectoryURL
                   pixelFormat:(MTLPixelFormat)pixelFormat NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;


- (nullable id<MTLRenderPipelineState>)pipelineStateForShaderPath:(NSString *)shaderPath;

@end

NS_ASSUME_NONNULL_END
