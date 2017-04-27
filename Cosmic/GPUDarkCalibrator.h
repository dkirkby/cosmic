#import "GPUImageFilterGroup.h"
#import "GPUImageBuffer.h"
#import "GPUImageDissolveBlendFilter.h"

@interface GPUDarkCalibrator : GPUImageFilterGroup
{
    GPUImageBuffer *bufferFilter;
    GPUImageDissolveBlendFilter *dissolveBlendFilter;
}

// Number of dark calibration frames collected so far
@property(readwrite, nonatomic) unsigned int nCalibrationFrames;

@end
