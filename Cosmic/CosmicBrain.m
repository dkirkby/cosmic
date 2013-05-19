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

#define VERBOSE NO

#define STAMP_SIZE 7
#define HISTORY_BUFFER_SIZE 128
#define MIN_INTENSITY 128
#define MAX_REPEATS 2

typedef enum {
    IDLE,
    BEGINNING,
    RUNNING
} CosmicState;

@interface CosmicBrain () {
    unsigned char *_pixelCount;
    NSDate *_beginAt;
}

@property(strong,nonatomic) AVCaptureDevice *bestDevice;
@property(strong,nonatomic) AVCaptureSession *captureSession;
@property(strong,nonatomic) AVCaptureStillImageOutput *cameraOutput;
@property CosmicState state;
@property int exposureCount;
@property(strong,nonatomic) NSDateFormatter *timestampFormatter;

@end

@implementation CosmicBrain

#pragma mark - Setters/Getters

- (NSMutableArray *)cosmicImages
{
    if(!_cosmicImages) _cosmicImages = [[NSMutableArray alloc] init];
    return _cosmicImages;
}

- (NSDateFormatter*)timestampFormatter
{
    if(!_timestampFormatter) {
        _timestampFormatter = [[NSDateFormatter alloc] init];
        [_timestampFormatter setDateFormat:@"YY-MM-dd-hh-mm-ss-SSS"];
    }
    return _timestampFormatter;
}

#pragma mark - Initialization

- (void) initCapture {
    if(VERBOSE) NSLog(@"initializing capture...");
    // Initialize a session with the photo preset
    self.captureSession = [[AVCaptureSession alloc] init];
    if([self.captureSession canSetSessionPreset:AVCaptureSessionPresetPhoto]) {
        self.captureSession.sessionPreset = AVCaptureSessionPresetPhoto;
    }
    else {
        if(VERBOSE) NSLog(@"Failed to set the photo session preset!");
    }
    // Look for a suitable input device (we look for "video" here since there is no separate still image type)
    NSArray *cameras=[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    if(cameras.count == 0) {
        if(VERBOSE) NSLog(@"No video devices available.");
        return;
    }
    self.bestDevice = nil;
    for(AVCaptureDevice *device in cameras) {
        // Look up this camera's capabilities
        BOOL exposureLock = [device isExposureModeSupported:AVCaptureExposureModeLocked];
        BOOL focusLock = [device isFocusModeSupported:AVCaptureFocusModeLocked];
        if(VERBOSE) NSLog(@"Found '%@' (exposure lock? %s; focus lock? %s)",device.localizedName,
              (exposureLock ? "yes":"no"),(focusLock ? "yes":"no"));
        // Is this the best so far?
        if(nil == self.bestDevice && exposureLock && focusLock) self.bestDevice = device;
    }
    if(nil == self.bestDevice) {
        if(VERBOSE) NSLog(@"PANIC: no suitable camera device available!");
        return;
    }
    if(VERBOSE) NSLog(@"Using '%@' to capture images.",self.bestDevice.localizedName);
    // Configure a capture session using the best device.
    NSError *error = nil;
    AVCaptureDeviceInput *input =
        [AVCaptureDeviceInput deviceInputWithDevice:self.bestDevice error:&error];
    if(!input) {
        if(VERBOSE) NSLog(@"PANIC: failed to configure device input!");
        return;
    }
    [self.captureSession addInput:input];
    // Configure and set the output device
    self.cameraOutput = [[AVCaptureStillImageOutput alloc] init];
    // perhaps kCVPixelFormatType_32ARGB is faster?
    // http://stackoverflow.com/questions/14383932/convert-cmsamplebufferref-to-uiimage
    NSDictionary *outputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA],
                                    (id)kCVPixelBufferPixelFormatTypeKey,
                                    nil];
    [self.cameraOutput setOutputSettings:outputSettings];
    [self.captureSession addOutput:self.cameraOutput];
    // Start the session running now
    [self.captureSession startRunning];
    // Initialize our state
    self.exposureCount = 0;
    self.state = IDLE;
}

#pragma mark - Initial Focus/Exposure Locking

- (void) beginCapture {
    NSLog(@"begin capture...");
    // Try to lock the exposure and focus for the best device.
    NSError *error = nil;
    if([self.bestDevice lockForConfiguration:&error]) {
        CGPoint center = CGPointMake(0.5,0.5);
        if([self.bestDevice isFocusPointOfInterestSupported]) {
            [self.bestDevice setFocusPointOfInterest:center];
            if(VERBOSE) NSLog(@"Set focus point of interest.");
        }
        if([self.bestDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
            [self.bestDevice setFocusMode:AVCaptureFocusModeAutoFocus];
            if(VERBOSE) NSLog(@"Autofocus successful.");
        }
        else if([self.bestDevice isFocusModeSupported:AVCaptureFocusModeLocked]) {
            [self.bestDevice setFocusMode:AVCaptureFocusModeLocked];
            if(VERBOSE) NSLog(@"Focus lock successful.");
        }
        if([self.bestDevice isExposurePointOfInterestSupported]) {
            [self.bestDevice setExposurePointOfInterest:center];
            if(VERBOSE) NSLog(@"Set exposure point of interest.");
        }
        if([self.bestDevice isExposureModeSupported:AVCaptureExposureModeAutoExpose]) {
            [self.bestDevice setExposureMode:AVCaptureExposureModeAutoExpose];
            if(VERBOSE) NSLog(@"Autoexposure successful.");
        }
        else if([self.bestDevice isExposureModeSupported:AVCaptureExposureModeLocked]) {
            [self.bestDevice setExposureMode:AVCaptureExposureModeLocked];
            if(VERBOSE) NSLog(@"Exposure lock successful.");
        }
        [self.bestDevice unlockForConfiguration];
        // Initialize our state
        self.state = BEGINNING;
        self.exposureCount = 0;
        // Capture an initial calibration image
        [self captureImage];
    }
    else {
        if(VERBOSE) NSLog(@"PANIC: cannot lock device for exposure and focus configuration.");
        return;
    }
}

#pragma mark - Capture

- (void) captureImage {
    if(self.state == IDLE) {
        if(VERBOSE) NSLog(@"Cannot captureImage before beginImage.");
        return;
    }
    if(VERBOSE) NSLog(@"capturing image in state %d...",self.state);
    [self.cameraOutput captureStillImageAsynchronouslyFromConnection:[[self.cameraOutput connections] objectAtIndex:0] completionHandler:^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
        
        // Get a timestamp for this capture
        NSDate *timestamp = [[NSDate alloc] init];
        
        // Lookup this frame's properties
        CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(imageSampleBuffer);
        CVPixelBufferLockBaseAddress(cameraFrame, 0);
        size_t width = CVPixelBufferGetWidth(cameraFrame);
        size_t height = CVPixelBufferGetHeight(cameraFrame);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(cameraFrame);
        int bytesPerPixel = bytesPerRow/width;
        if(VERBOSE) NSLog(@"processing raw data %lu x %lu with %d bytes per pixel",width,height,bytesPerPixel);

        /**
        // Lookup this image's metadata
        CFDictionaryRef exifAttachments = CMGetAttachment(imageSampleBuffer, kCGImagePropertyExifDictionary, NULL);
        if (exifAttachments) {
            // Do something with the attachments.
            if(VERBOSE) NSLog(@"attachements: %@", exifAttachments);
        }
        else {
            if(VERBOSE) NSLog(@"no attachments");
        }
        CFNumberRef shutter = CMGetAttachment( imageSampleBuffer, kCGImagePropertyExifShutterSpeedValue, NULL);
        if(VERBOSE) NSLog(@"\n shuttervalue : %@",shutter);
         **/

        // Look at the actual image data. Each pixel is stored as four bytes. When accessed
        // as an unsigned int, the bytes are packed as (A << 24) | (B << 16) | (G << 8) | R.
        // The first pixel in the buffer corresponds to the top-right corner of the sensor
        // (when the device is held in its normal portrait orientation). Pixels increase
        // fastest along the "width", which actually moves down in the image from the top-right
        // corner. After each width pixels, the image data moves down one row, or left in the
        // sensor. The last pixel corresponds to the bottom-left corner of the sensor.
        GLubyte *rawImageBytes = CVPixelBufferGetBaseAddress(cameraFrame);

        if(self.state == BEGINNING) {
            // The first image is for locking focus and exposure only.
            // Now that we know the image dimensions, initialize an array to count how often each pixel
            // is selected as the maximum intensity in an exposure.
            if(_pixelCount) free(_pixelCount);
            int countSize = sizeof(unsigned char)*width*height;
            _pixelCount = malloc(countSize);
            bzero(_pixelCount,countSize);
            NSLog(@"Initialized for %ld x %ld images",width,height);
            _beginAt = [timestamp copy];
            self.state = RUNNING;
        }
        else { // RUNNING
            // Loop over raw pixels to find the pixel with the largest intensity r+2*g+b
            unsigned int maxIntensity = MIN_INTENSITY;
            unsigned maxIndex = width*height, lastIndex = width*height, index = 0;
            unsigned int *bufptr = (unsigned int *)rawImageBytes;
            unsigned char *countPtr = _pixelCount;
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
                }
                index++;
            }
            // Did we find a candidate in this exposure?
            if(maxIndex != lastIndex) {
                
                // Convert the candidate index back to (x,y) coordinates in the raw image
                int maxX = maxIndex%width;
                int maxY = maxIndex/width;

                // Create a unique string identifier for this capture
                NSString *identifier = [[NSString alloc] initWithFormat:@"stamp_%@_%04d-%04d",[self.timestampFormatter stringFromDate:timestamp],maxX,maxY];
                NSLog(@"Found max intensity %d at %@",maxIntensity,identifier);
                
                // Update our counts for this pixel
                _pixelCount[maxIndex]++;
                
                // Save a stamp centered (as far as possible) around maxX,maxY
                int x1 = maxX - STAMP_SIZE, x2 = maxX + STAMP_SIZE;
                if(x1 < 0) { x1 = 0; x2 = 2*STAMP_SIZE; }
                else if(x2 >= width) { x2 = width-1; x1 = width - 2*STAMP_SIZE - 1; }
                int y1 = maxY - STAMP_SIZE, y2 = maxY + STAMP_SIZE;
                if(y1 < 0) { y1 = 0; y2 = 2*STAMP_SIZE; }
                else if(y2 >= height) { y2 = height-1; y1 = height - 2*STAMP_SIZE - 1; }
                [self saveImageDataWithIdentifier:identifier Width:2*STAMP_SIZE+1 Height:2*STAMP_SIZE+1 AtLeftEdge:x1 TopEdge:y1 FromRawData:rawImageBytes WithRawWidth:width RawHeight:height];
            }
            // Save fixed sub-image in first exposure, for debugging
            if(false && self.exposureCount == 0) {
                UIImage *img = [self createUIImageWithWidth:64 Height:64 AtLeftEdge:750 TopEdge:500 FromRawData:rawImageBytes WithRawWidth:width RawHeight:height];
                [self saveImageToFilesystem:img withIdentifier:@"testing"];
            }
            
            self.exposureCount++;
            if(self.exposureCount > 1 && self.exposureCount % 10 == 0) {
                NSTimeInterval elapsed = [timestamp timeIntervalSinceDate:_beginAt];
                NSLog(@"Exposure capture rate = %.3f / sec",elapsed/self.exposureCount);
            }
        }

        // All done with the image buffer so release it now
        CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
        
        // Update our delegate on the UI thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.brainDelegate setExposureCount:self.exposureCount];
            //[self.brainDelegate imageAdded];
            [self captureImage];

        });
    }];
}

- (void) saveImageToFilesystem:(UIImage*)image withIdentifier:(NSString*)identifier {
    // Add this sub-image to our list of saved images
    NSURL *docsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *pathComponent = [NSString stringWithFormat:@"%@.png",identifier];
    NSURL *imageURL = [docsDirectory URLByAppendingPathComponent:pathComponent];
    NSError *writeError;
    [UIImagePNGRepresentation(image) writeToURL:imageURL options:NSDataWritingAtomic error:&writeError];
    //[UIImageJPEGRepresentation(image,1.0) writeToURL:imageURL options:NSDataWritingAtomic error:&writeError];
    if(VERBOSE) NSLog(@"Written To Filesystem at %@", imageURL);
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
        
        for(int x = 0; x < imageWidth; ++x) {
            unsigned int val = imgPtr[x];
            unsigned char R = (val & 0xff), G = (val & 0xff00) >> 8, B = (val & 0xff0000) >> 16, A = val>>24;
            unsigned int intensity = R+2*G+B;
            NSLog(@"dump (%d,%d) R=%d G=%d B=%d A=%d I=%d",x,y,R,G,B,A,intensity);
        }
        
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

@end
