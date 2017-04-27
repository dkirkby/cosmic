#import "GPUDarkCalibrator.h"

@interface GPUDarkCalibrator () {
    int _frameCounter;
}
@end

@implementation GPUDarkCalibrator

- (id)init;
{
    if (!(self = [super init]))
    {
		return nil;
    }
    
    // Take in the frame and blend it with the previous one
    dissolveBlendFilter = [[GPUImageDissolveBlendFilter alloc] init];
    [self addFilter:dissolveBlendFilter];
    
    // Buffer the result to be fed back into the blend
    bufferFilter = [[GPUImageBuffer alloc] init];
    [self addFilter:bufferFilter];
    
    // Texture location 0 needs to be the original image for the dissolve blend
    [bufferFilter addTarget:dissolveBlendFilter atTextureLocation:1];
    [dissolveBlendFilter addTarget:bufferFilter];
    
    [dissolveBlendFilter disableSecondFrameCheck];
    
    // To prevent double updating of this filter, disable updates from the sharp image side
    //    self.inputFilterToIgnoreForUpdates = unsharpMaskFilter;
    
    self.initialFilters = [NSArray arrayWithObject:dissolveBlendFilter];
    self.terminalFilter = dissolveBlendFilter;
    
    self.nCalibrationFrames = 0;
    
    __unsafe_unretained GPUDarkCalibrator *weakSelf = self;
    [self setFrameProcessingCompletionBlock:^(GPUImageOutput *filter, CMTime frameTime) {
        int n = ++weakSelf.nCalibrationFrames;
        // ouptut = (1-mix)*input + mix*last_output
        // use one-pass online updating to accumulate the mean frame with mix = (n-1)/n
        weakSelf->dissolveBlendFilter.mix = (n-1.0)/n;
    }];
    
    return self;
}

@end
