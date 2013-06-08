#import "GPUImageFilter.h"

extern NSString *const kGPUCosmicDiscriminatorVertexShaderString;

@interface GPUCosmicDiscriminator : GPUImageFilter
{
    GLint texelWidthUniform, texelHeightUniform;
    
    NSUInteger numberOfStages;
    NSMutableArray *stageTextures, *stageFramebuffers, *stageSizes;
    
    GLubyte *rawImagePixels;
}

// This block is called on the completion of color averaging for a frame
@property(nonatomic, copy) void(^cosmicDiscriminatorFinishedBlock)(CMTime frameTime);

- (void)finalizeAtFrameTime:(CMTime)frameTime;

@end
