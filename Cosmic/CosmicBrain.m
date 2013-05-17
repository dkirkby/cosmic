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

#define CALIB_SIZE 16
#define STAMP_SIZE 15

typedef enum {
    IDLE,
    BEGINNING,
    CALIBRATING,
    RUNNING
} CosmicState;

@interface CosmicBrain ()

@property AVCaptureDevice *bestDevice;
@property AVCaptureSession *captureSession;
@property AVCaptureStillImageOutput *cameraOutput;
@property CosmicState state;
@property int exposureCount;
@property float *calibMean, *calibRMS;
@property unsigned int *calibCount;

@end

@implementation CosmicBrain

#pragma mark - Setters/Getters

- (NSMutableArray *)cosmicImages
{
    if(!_cosmicImages) _cosmicImages = [[NSMutableArray alloc] init];
    return _cosmicImages;
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
    self.state = IDLE;
}

#pragma mark - Initial Focus/Exposure Locking

- (void) beginCapture {
    self.state = BEGINNING;
    if(VERBOSE) NSLog(@"begin capture...");
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
        
        // Lookup this frame's properties
        CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(imageSampleBuffer);
        CVPixelBufferLockBaseAddress(cameraFrame, 0);
        size_t width = CVPixelBufferGetWidth(cameraFrame);
        size_t height = CVPixelBufferGetHeight(cameraFrame);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(cameraFrame);
        int bytesPerPixel = bytesPerRow/width;
        if(VERBOSE) NSLog(@"processing raw data %lu x %lu with %d bytes per pixel",width,height,bytesPerPixel);

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

        // Look at the actual image data
        GLubyte *rawImageBytes = CVPixelBufferGetBaseAddress(cameraFrame);

        if(self.state == BEGINNING) {
            // The first image is for locking focus and exposure only.
            // go directly to RUNNING and skip CALIBRATING step for now
            self.state = RUNNING;
        }
        else if(self.state == CALIBRATING) {
            // Calculate the dimensions of the coarse calibration grid
            if(width % CALIB_SIZE || height % CALIB_SIZE) {
                if(VERBOSE) NSLog(@"WARNING: CALIB_SIZE does not divide evenly into the image size");
            }
            int calibWidth = (width+CALIB_SIZE-1)/CALIB_SIZE;
            int calibHeight = (height+CALIB_SIZE-1)/CALIB_SIZE;
            size_t calibSize = sizeof(float)*calibWidth*calibHeight;
            if(VERBOSE) NSLog(@"Calibrating on %d x %d grid...",calibWidth,calibHeight);
            // Allocate memory for calibration data
            if(self.calibMean) free(self.calibMean);
            self.calibMean = malloc(calibSize);
            bzero(self.calibMean,calibSize);
            if(self.calibRMS) free(self.calibRMS);
            self.calibRMS = malloc(calibSize);
            bzero(self.calibRMS,calibSize);
            calibSize = sizeof(unsigned int)*calibWidth*calibHeight;
            if(self.calibCount) free(self.calibCount);
            self.calibCount = malloc(calibSize);
            bzero(self.calibCount,calibSize);
            // Loop over raw pixels to accumulate calibration statistics
            unsigned const char *bufptr = rawImageBytes;
            for(int y = 0; y < height; ++y) {
                int ycalib = y/CALIB_SIZE;
                for(int x = 0; x < width; ++x) {
                    int xcalib = x/CALIB_SIZE;
                    int calibAddr = ycalib*calibWidth+xcalib;
                    unsigned char r = *bufptr++, g = *bufptr++, b = *bufptr++;
                    bufptr++; // ignore the alpha channel
                    float intensity = r+g+b;
                    self.calibMean[calibAddr] += intensity;
                    self.calibRMS[calibAddr] += intensity*intensity;
                    self.calibCount[calibAddr]++;
                }
            }
            // Loop over calibration grid to finalize statistics
            for(int ycalib = 0; ycalib < calibHeight; ++ycalib) {
                for(int xcalib = 0; xcalib < calibWidth; ++xcalib) {
                    int calibAddr = ycalib*calibWidth+xcalib;
                    float count = self.calibCount[calibAddr];
                    float mean = self.calibMean[calibAddr]/count;
                    float var = self.calibRMS[calibAddr]/count - mean*mean;
                    self.calibMean[calibAddr] = mean;
                    self.calibRMS[calibAddr] = var > 0 ? sqrt(var) : 0;
                }
            }
            self.state = RUNNING;
        }
        else { // RUNNING
            // Loop over raw pixels to find the pixel with the largest intensity r+2*g+b
            unsigned int maxIntensity = 0;
            unsigned maxIndex, lastIndex = width*height, index = 0;
            unsigned int *bufptr = (unsigned int *)rawImageBytes;
            while(index < lastIndex) {
                unsigned int val = *bufptr++;
                // val = (A << 24) | (B << 16) | (G << 8) | R
                // we only shift G component by 7 so that it gets multiplied by 2
                unsigned int intensity = ((val&0xff0000) >> 16) + ((val&0xff00) >> 7) + (val&0xff);
                if(intensity > maxIntensity) {
                    maxIntensity = intensity;
                    maxIndex = index;
                }
                index++;
            }
            int maxY = index/width;
            int maxX = index%height;
            NSLog(@"Found max intensity %d at index %d (%d,%d)",maxIntensity,maxIndex,maxX,maxY);
            
            // Save a stamp centered (as far as possible) around maxX,maxY
            int x1 = maxX - STAMP_SIZE, x2 = maxX + STAMP_SIZE;
            if(x1 < 0) x1 = 0;
            else if(x2 >= width) x2 = width-1;
            int y1 = maxY - STAMP_SIZE, y2 = maxY + STAMP_SIZE;
            if(y1 < 0) y1 = 0;
            else if(y2 >= height) y2 = height-1;
            UIImage *stamp = [self createUIImageWithWidth:(x2-x1+1) Height:(y2-y1+1) AtLeftEdge:x1 TopEdge:y1 FromRawData:rawImageBytes WithRawWidth:width RawHeight:height];
            [self.cosmicImages addObject:stamp];
            
            /***
            UIImage *image = [self createUIImageWithWidth:width Height:height AtLeftEdge:0 TopEdge:0 FromRawData:rawImageBytes WithRawWidth:width RawHeight:height];

            // Add this sub-image to our list of saved images
            NSURL *docsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
            NSString *pathComponent = [NSString stringWithFormat:@"%@.png", [NSDate date]];
            NSURL *imageURL = [docsDirectory URLByAppendingPathComponent:pathComponent];
            NSError *writeError;
            [UIImagePNGRepresentation(image) writeToURL:imageURL options:NSDataWritingAtomic error:&writeError];
            NSLog(@"Written To Filesystem at %@", imageURL);
            if(writeError) NSLog(@"Write to Filesystem Error: %@", writeError.userInfo);
            ***/
            self.exposureCount++;
        }

        // All done with the image buffer so release it now
        CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
                
        // Update our delegate on the UI thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.brainDelegate setExposureCount:self.exposureCount];
            [self.brainDelegate imageAdded];
        });
    }];
}

- (UIImage*) createUIImageWithWidth:(int)imageWidth Height:(int)imageHeight AtLeftEdge:(int)leftEdge TopEdge:(int)topEdge FromRawData:(unsigned char *)rawData WithRawWidth:(int)rawWidth RawHeight:(int)rawHeight {

    UIGraphicsBeginImageContext(CGSizeMake(imageWidth,imageHeight));
    CGContextRef c = UIGraphicsGetCurrentContext();
    unsigned char* imgData = CGBitmapContextGetData(c);

    size_t bytesPerImgRow = 4*imageWidth, bytesPerRawRow = 4*rawWidth;
    for(int y = topEdge; y < topEdge + imageHeight; ++y) {
        size_t imgOffset = (y-topEdge)*bytesPerImgRow;
        size_t rawOffset = y*bytesPerRawRow + 4*leftEdge;
        memcpy(imgData+imgOffset, rawData+rawOffset, bytesPerImgRow);
    }
    
    //quick fix to sideways image problem
    UIImage *image = [[UIImage alloc] initWithCGImage:UIGraphicsGetImageFromCurrentImageContext().CGImage scale:1.0 orientation:UIImageOrientationRight];
 
    UIGraphicsEndImageContext();
    
    return image;
}

@end
