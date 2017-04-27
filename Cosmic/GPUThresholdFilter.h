#import "GPUImageFilter.h"

/** Pixels with a luminance above the threshold will appear white, and those below will be black
 */
@interface GPUThresholdFilter : GPUImageFilter
{
    GLint thresholdUniform;
}

/** Intensity is defined as R+2G+B, rescaled to the range 0-1. Any pixels whose itensity is below
 the specified threshold will have their alpha channel set to 0. The remaining pixels will be
 unaffected.
 */
@property(readwrite, nonatomic) CGFloat threshold; 

@end
