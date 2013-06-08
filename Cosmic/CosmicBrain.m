//
//  CosmicBrain.m
//  Cosmic
//
//  Created by David Kirkby on 3/11/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import "CosmicBrain.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import "CosmicStamp.h"

#import "GPUImage.h"
#import "GPUThresholdFilter.h"
#import "GPUDarkCalibrator.h"

#define VERBOSE NO

#define MIN_INTENSITY 256 // 64
#define MAX_REPEATS 4
#define STATS_UPDATE_INTERVAL 10 // # of exposures between NSLog updates

@interface CosmicBrain () {
    unsigned char *_pixelCount;
    int _width, _height;
    unsigned long _exposureCount, _saveCount;
    GPUImageVideoCamera *_videoCamera;
    GPUDarkCalibrator *_darkCalibrator;
    GPUThresholdFilter *_threshold;
    GPUImageLuminosity *_luminosity;
    GPUImageRawDataOutput *_finishCalibration, *_rawDataOutput;
    CMTime _timestamp0,_timestamp;
}

@property(strong,nonatomic) NSDateFormatter *timestampFormatter;

@end

@implementation CosmicBrain

#pragma mark - Setters/Getters

- (NSMutableArray *)cosmicStamps
{
    if(!_cosmicStamps) _cosmicStamps = [[NSMutableArray alloc] init];
    return _cosmicStamps;
}

- (NSDateFormatter*)timestampFormatter
{
    if(!_timestampFormatter) {
        _timestampFormatter = [[NSDateFormatter alloc] init];
        [_timestampFormatter setDateFormat:@"YY-MM-dd-HH-mm-ss-SSS"];
    }
    return _timestampFormatter;
}

#pragma mark - Initialization

- (void) initCapture {
    
    _videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:AVCaptureSessionPreset1280x720 cameraPosition:AVCaptureDevicePositionBack];
    _width = 1280;
    _height = 720;
    
    _videoCamera.outputImageOrientation = UIInterfaceOrientationLandscapeLeft;
    _videoCamera.horizontallyMirrorFrontFacingCamera = NO;
    _videoCamera.horizontallyMirrorRearFacingCamera = NO;
    _videoCamera.runBenchmark = NO;
    
    _darkCalibrator = [[GPUDarkCalibrator alloc] init];
    
    _threshold = [[GPUThresholdFilter alloc] init];
    _threshold.threshold = MIN_INTENSITY/1024.0;
    
    // Use this voodoo to avoid warnings about 'capturing self strongly in this block is likely to lead to a retain cycle'
    // http://stackoverflow.com/questions/14556605/capturing-self-strongly-in-this-block-is-likely-to-lead-to-a-retain-cycle
    __unsafe_unretained typeof(self) my = self;
    
    // See http://stackoverflow.com/questions/12168072/fragment-shader-average-luminosity/12169560#12169560
    // for details on how the image luminosity is calculated on the GPU. For a similar max finder, see
    // http://stackoverflow.com/questions/12488049/glsl-how-to-access-pixel-data-of-a-texture-is-glsl-shader
    _luminosity = [[GPUImageLuminosity alloc] init];
    _luminosity.luminosityProcessingFinishedBlock = ^(CGFloat luminosity, CMTime frameTime) {
        if(my->_exposureCount % STATS_UPDATE_INTERVAL == 0) {
            if(my->_exposureCount > 0) {
                Float64 elapsed = CMTimeGetSeconds(CMTimeSubtract(frameTime, my->_timestamp0));
                NSLog(@"saved %lu of %lu exposures (fps = %.3f)",my->_saveCount,my->_exposureCount,STATS_UPDATE_INTERVAL/elapsed);
            }
            my->_timestamp0 = frameTime;
        }
        
        // Update our exposure counter
        my->_exposureCount++;

        // Flag this frame for further processing?
        if(luminosity > 0.0) {
            my->_timestamp = frameTime;
            NSLog(@"finished detection pipeline for %f",CMTimeGetSeconds(my->_timestamp));
        }
        else {
            my->_timestamp = kCMTimeInvalid;
        }
    };
    
    _finishCalibration = [[GPUImageRawDataOutput alloc] initWithImageSize:CGSizeMake(1280.0, 720.0) resultsInBGRAFormat:YES];
    [_finishCalibration setNewFrameAvailableBlock:^{
        NSLog(@"Saving calibration.");
        // Save the raw data as in image
        GLubyte *rawImageBytes = [my->_finishCalibration rawBytesForImage];
        UIImage *img = [my createUIImageWithWidth:my->_width Height:my->_height AtLeftEdge:0 TopEdge:0 FromRawData:rawImageBytes WithRawWidth:my->_width RawHeight:my->_height];
        [my saveImageToFilesystem:img withIdentifier:@"calibration"];
        // Don't take any more frames
        [my->_videoCamera stopCameraCapture];
    }];
    
    _rawDataOutput = [[GPUImageRawDataOutput alloc] initWithImageSize:CGSizeMake(1280.0, 720.0) resultsInBGRAFormat:YES];
    [_rawDataOutput setNewFrameAvailableBlock:^{
        
        // Did the previous filters flag this frame?
        if(CMTIME_IS_INVALID(my->_timestamp)) return;
        NSLog(@"starting raw pipeline for %f",CMTimeGetSeconds(my->_timestamp));
        
        // Get a pointer to our raw image data. Each pixel is stored as four bytes. When accessed
        // as an unsigned int, the bytes are packed as (A << 24) | (B << 16) | (G << 8) | R.
        // The first pixel in the buffer corresponds to the top-right corner of the sensor
        // (when the device is held in its normal portrait orientation). Pixels increase
        // fastest along the "width", which actually moves down in the image from the top-right
        // corner. After each width pixels, the image data moves down one row, or left in the
        // sensor. The last pixel corresponds to the bottom-left corner of the sensor.
        GLubyte *rawImageBytes = [my->_rawDataOutput rawBytesForImage];
        
        // Sanity check: dump first exposure as a full image
        if(false && 0 == my->_exposureCount) {
            UIImage *img = [my createUIImageWithWidth:my->_width Height:my->_height AtLeftEdge:0 TopEdge:0 FromRawData:rawImageBytes WithRawWidth:my->_width RawHeight:my->_height];
            [my saveImageToFilesystem:img withIdentifier:@"testing"];
        }
        
        // Run the analysis algorithm
        // Loop over raw pixels to find the pixel with the largest intensity r+2*g+b
        unsigned int maxIntensity = MIN_INTENSITY;
        unsigned maxIndex = my->_width*my->_height, index = 0;
        unsigned lastIndex = maxIndex;
        unsigned int *bufptr = (unsigned int *)rawImageBytes;
        unsigned char *countPtr = my->_pixelCount;
        while(index < lastIndex) {
            // get the next 32-bit word of pixel data and advance our buffer pointer
            unsigned int val = *bufptr++;
            // skip hot pixels
            if(*countPtr++ < MAX_REPEATS) {
                // val = (A << 24) | (B << 16) | (G << 8) | R
                // we only shift G component by 7 so that it gets multiplied by 2
                unsigned int intensity = ((val&0xff0000) >> 16) + ((val&0xff00) >> 7) + (val&0xff);
                if(intensity > maxIntensity) {
                    maxIntensity = intensity;
                    maxIndex = index;
                }
                //NSLog(@"%6d %08x %u %u",index,val,intensity,maxIntensity);
            }
            index++;
        }

        // Did we find a candidate in this exposure?
        if(maxIndex != lastIndex) {
            
            // Update our counts for this pixel
            my->_pixelCount[maxIndex]++;
            
            /***
            // Convert the candidate index back to (x,y) coordinates in the raw image
            int maxX = maxIndex%my->_width;
            int maxY = maxIndex/my->_width;
            
            // Calculate stamp bounds [x1,y1]-[x2,y2] that are centered (as far as possible)
            // around maxX,maxY
            int x1 = maxX - STAMP_SIZE, x2 = maxX + STAMP_SIZE;
            if(x1 < 0) { x1 = 0; x2 = 2*STAMP_SIZE; }
            else if(x2 >= my->_width) { x2 = my->_width-1; x1 = my->_width - 2*STAMP_SIZE - 1; }
            int y1 = maxY - STAMP_SIZE, y2 = maxY + STAMP_SIZE;
            if(y1 < 0) { y1 = 0; y2 = 2*STAMP_SIZE; }
            else if(y2 >= my->_height) { y2 = my->_height-1; y1 = my->_height - 2*STAMP_SIZE - 1; }
            
            // Create our Stamp structure
            CosmicStamp *stamp = [[CosmicStamp alloc] init];
            stamp.elapsedMSecs = (uint32_t)(1e3*[timestamp timeIntervalSinceDate:_beginAt]);
            stamp.maxPixelIndex = maxIndex;
            stamp.exposureCount = my->_exposureCount;
            uint8_t *rgbPtr = stamp.rgb;
            
            uint32_t *rawPtr = (uint32_t*)rawImageBytes + y1*my->_width + x1;
            for(int y = 0; y < 2*STAMP_SIZE+1; ++y) {
                for(int x = 0; x < 2*STAMP_SIZE+1; ++x) {
                    uint32_t raw = rawPtr[x]; // raw = AABBGGRR
                    *rgbPtr++ = (raw & 0xff); // Red
                    *rgbPtr++ = (raw & 0xff00) >> 8; // Green
                    *rgbPtr++ = (raw & 0xff0000) >> 16; // Blue
                }
                rawPtr += my->_width;
            }
            
            // Save our Stamp structure to disk
            NSString *filename = [[NSString alloc] initWithFormat:@"stamp_%@.dat",[self.timestampFormatter stringFromDate:timestamp]];
            [self saveStamp:stamp ToFilename:filename];
            [self.cosmicStamps addObject:stamp];
            
            // Update our delegate on the UI thread
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.brainDelegate stampAdded];
            });
            ***/
            
            my->_saveCount++;
        }
    }];
    
    // Now that we know the image dimensions, initialize an array to count how often each pixel
    // is selected as the maximum intensity in an exposure.
    if(_pixelCount) free(_pixelCount);
    int countSize = sizeof(unsigned char)*_width*_height;
    _pixelCount = malloc(countSize);
    bzero(_pixelCount,countSize);
}

- (void) lockExposureAndFocus {
    NSError *error = nil;
    AVCaptureDevice *device = _videoCamera.inputCamera;
    if([device lockForConfiguration:&error]) {
        CGPoint center = CGPointMake(0.5,0.5);
        if([device isFocusPointOfInterestSupported]) {
            [device setFocusPointOfInterest:center];
            NSLog(@"Set focus point of interest.");
        }
        if([device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
            [device setFocusMode:AVCaptureFocusModeAutoFocus];
            NSLog(@"Autofocus successful.");
        }
        else if([device isFocusModeSupported:AVCaptureFocusModeLocked]) {
            [device setFocusMode:AVCaptureFocusModeLocked];
            NSLog(@"Focus lock successful.");
        }
        if([device isExposurePointOfInterestSupported]) {
            [device setExposurePointOfInterest:center];
            NSLog(@"Set exposure point of interest.");
        }
        if([device isExposureModeSupported:AVCaptureExposureModeAutoExpose]) {
            [device setExposureMode:AVCaptureExposureModeAutoExpose];
            NSLog(@"Autoexposure successful.");
        }
        else if([device isExposureModeSupported:AVCaptureExposureModeLocked]) {
            [device setExposureMode:AVCaptureExposureModeLocked];
            NSLog(@"Exposure lock successful.");
        }
        [device unlockForConfiguration];
    }
    else {
        NSLog(@"PANIC: cannot lock device for exposure and focus configuration.");
        return;
    }
}

- (void) beginCalibration {
    // Try to lock the exposure and focus.
    [self lockExposureAndFocus];
    
    // Configure the GPU pipeline for calibration
    [_videoCamera removeAllTargets];
    [_videoCamera addTarget:_darkCalibrator];
    _darkCalibrator.nCalibrationFrames = 0;
    
    // Start the calibration process running
    NSLog(@"starting calibration...");
    [_videoCamera startCameraCapture];
}

- (void) endCalibration {
    // Add the finishCalibration target to the end of our chain for the next frame
    [_darkCalibrator addTarget:_finishCalibration];
    NSLog(@"Finishing calibration after %d frames.", _darkCalibrator.nCalibrationFrames);
}

- (void) beginCapture {
    
    [self beginCalibration];
    double delayInSeconds = 10.0;
    dispatch_time_t stopTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(stopTime, dispatch_get_main_queue(), ^(void){
        [self endCalibration];
    });

/**
    // Initialize data for this run
    _saveCount = 0;
    _exposureCount = 0;
    
    // Configure the GPU pipeline for data taking
    [_videoCamera removeAllTargets];
    [_threshold removeAllTargets];
    [_videoCamera addTarget:_threshold];
    [_threshold addTarget: _luminosity];
    [_videoCamera addTarget:_rawDataOutput];

    // Start the capture process running
    [_videoCamera startCameraCapture];
**/
}

- (void) saveImageToFilesystem:(UIImage*)image withIdentifier:(NSString*)identifier {
    // Add this sub-image to our list of saved images
    NSURL *docsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *pathComponent = [NSString stringWithFormat:@"%@.png",identifier];
    NSURL *imageURL = [docsDirectory URLByAppendingPathComponent:pathComponent];
    NSError *writeError;
    [UIImagePNGRepresentation(image) writeToURL:imageURL options:NSDataWritingAtomic error:&writeError];
    //[UIImageJPEGRepresentation(image,1.0) writeToURL:imageURL options:NSDataWritingAtomic error:&writeError];
    NSLog(@"Written To Filesystem at %@", imageURL);
    if(writeError) NSLog(@"Write to Filesystem Error: %@", writeError.userInfo);    
}

- (UIImage*) createUIImageWithWidth:(int)imageWidth Height:(int)imageHeight AtLeftEdge:(int)leftEdge TopEdge:(int)topEdge FromRawData:(unsigned char *)rawData WithRawWidth:(int)rawWidth RawHeight:(int)rawHeight {

    UIGraphicsBeginImageContext(CGSizeMake(imageWidth,imageHeight));
    CGContextRef c = UIGraphicsGetCurrentContext();

    // Initialize pointers to the top-left corner of the destination image and the source
    // rectangle in the raw data.
    unsigned int *imgPtr = (unsigned int*)CGBitmapContextGetData(c);
    unsigned int *rawPtr = (unsigned int*)rawData + topEdge*rawWidth + leftEdge;
    size_t bytesPerImgRow = 4*imageWidth;
    
    // Loop over rows to copy from the raw data into the image data array
    for(int y = 0; y < imageHeight; ++y) {
        memcpy(imgPtr,rawPtr,bytesPerImgRow);
        /**
        if(y < 4) {
            for(int x = 0; x < 4; ++x) {
                unsigned int val = imgPtr[x];
                unsigned char R = (val & 0xff), G = (val & 0xff00) >> 8, B = (val & 0xff0000) >> 16, A = val>>24;
                unsigned int intensity = R+2*G+B;
                NSLog(@"dump (%d,%d) R=%d G=%d B=%d A=%d I=%d",x,y,R,G,B,A,intensity);
            }
        }
        **/
        imgPtr += imageWidth;
        rawPtr += rawWidth;
    }
    
    //quick fix to sideways image problem
    UIImage *image = [[UIImage alloc] initWithCGImage:UIGraphicsGetImageFromCurrentImageContext().CGImage scale:1.0 orientation:UIImageOrientationRight];
 
    UIGraphicsEndImageContext();
    
    return image;
}

- (void) saveImageDataWithIdentifier:(NSString*)identifier Width:(int)imageWidth Height:(int)imageHeight AtLeftEdge:(int)leftEdge TopEdge:(int)topEdge FromRawData:(unsigned char *)rawData WithRawWidth:(int)rawWidth RawHeight:(int)rawHeight {
    
    if(VERBOSE) NSLog(@"Saving %@...",identifier);

    // Add this sub-image to our list of saved images
    NSURL *docsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *pathComponent = [NSString stringWithFormat:@"%@.dat",identifier];
    const char *filename = [[[docsDirectory URLByAppendingPathComponent:pathComponent] path] cStringUsingEncoding:NSASCIIStringEncoding];
    FILE *out = fopen(filename,"w");

    // Initialize pointer to the top-left corner of the source rectangle in the raw data.
    unsigned int *rawPtr = (unsigned int*)rawData + topEdge*rawWidth + leftEdge;
    
    // Loop over rows in the output image
    for(int y = 0; y < imageHeight; ++y) {
        for(int x = 0; x < imageWidth; ++x) {
            unsigned int val = rawPtr[x];
            unsigned char R = (val & 0xff), G = (val & 0xff00) >> 8, B = (val & 0xff0000) >> 16;
            fprintf(out,"  %4d %4d %4d",R,G,B);
        }
        fprintf(out,"\n");
        rawPtr += rawWidth;
    }
    fclose(out);
}

- (void) saveStamp:(CosmicStamp*)stamp ToFilename:(NSString*)filename {
/**
    NSLog(@"Saving stamp: elapsed = %u, index = %u, count = %u",_theStamp->elapsedMSecs,_theStamp->maxPixelIndex,_theStamp->exposureCount);
    uint8_t *ptr = _theStamp->rgb;
    for(int y = 0; y < 2*STAMP_SIZE+1; ++y) {
        for(int x = 0; x < 2*STAMP_SIZE+1; ++x) {
            uint8_t R= *ptr++, G = *ptr++, B = *ptr++;
            NSLog(@"[%2d,%2d] = (%3d,%3d,%3d) %4d",x,y,R,G,B,R+2*G+B);
        }
    }
**/
    // Generate the filename for this stamp
    NSURL *docsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    const char *fullName = [[[docsDirectory URLByAppendingPathComponent:filename] path] cStringUsingEncoding:NSASCIIStringEncoding];

    // Save the stamp in binary format
    FILE *out = fopen(fullName,"wb");
    uint32_t buffer;
    buffer = stamp.elapsedMSecs;
    fwrite(&buffer, sizeof(uint32_t), 1, out);
    
    buffer = stamp.maxPixelIndex;
    fwrite(&buffer, sizeof(uint32_t), 1, out);
    
    buffer = stamp.exposureCount;
    fwrite(&buffer, sizeof(uint32_t), 1, out);
    
    fwrite(stamp.rgb, sizeof(uint8_t), [CosmicStamp rgbSize], out);

    fclose(out);
}

@end
