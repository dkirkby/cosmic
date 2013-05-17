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

#define STAMP_SIZE 15
#define HISTORY_BUFFER_SIZE 16
#define MIN_INTENSITY 128

typedef enum {
    IDLE,
    BEGINNING,
    RUNNING
} CosmicState;

@interface CosmicBrain () {
    unsigned int *_historyBuffer;
}

@property AVCaptureDevice *bestDevice;
@property AVCaptureSession *captureSession;
@property AVCaptureStillImageOutput *cameraOutput;
@property CosmicState state;
@property int exposureCount;

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
    // Initialize our history buffer
    if(_historyBuffer) free(_historyBuffer);
    _historyBuffer = malloc(sizeof(unsigned int)*HISTORY_BUFFER_SIZE);
    // Initialize our state
    self.exposureCount = 0;
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
            self.state = RUNNING;
        }
        else { // RUNNING
            // Loop over raw pixels to find the pixel with the largest intensity r+2*g+b
            unsigned int maxIntensity = MIN_INTENSITY;
            unsigned maxIndex = width*height, lastIndex = width*height, index = 0;
            unsigned int *bufptr = (unsigned int *)rawImageBytes;
            while(index < lastIndex) {
                // get the next 32-bit word of pixel data and advance our buffer pointer
                unsigned int val = *bufptr++;
                // val = (A << 24) | (B << 16) | (G << 8) | R
                // we only shift G component by 7 so that it gets multiplied by 2
                unsigned int intensity = ((val&0xff0000) >> 16) + ((val&0xff00) >> 7) + (val&0xff);
                if(intensity > maxIntensity) {
                    // is this index in our history?
                    int hindex = self.exposureCount;
                    if(hindex > HISTORY_BUFFER_SIZE) hindex = HISTORY_BUFFER_SIZE;
                    while(hindex > 0 && _historyBuffer[--hindex] != index) ;
                    if(_historyBuffer[hindex] == index) {
                        NSLog(@"Masking hot pixel %d in exposure %d",index,self.exposureCount);
                    }
                    else {
                        maxIntensity = intensity;
                        maxIndex = index;
                    }
                }
                index++;
            }
            // Did we find a candidate in this exposure?
            if(maxIndex != lastIndex) {
                // Add this candidate to our history
                _historyBuffer[self.exposureCount % HISTORY_BUFFER_SIZE] = maxIndex;
                // Convert the candidate index back to (x,y) coordinates in the raw image
                int maxX = maxIndex%width;
                int maxY = maxIndex/width;
                NSLog(@"Found max intensity %d at index %d (%d,%d) in exposure %d",
                      maxIntensity,maxIndex,maxX,maxY,self.exposureCount);
                
                // Save a stamp centered (as far as possible) around maxX,maxY
                int x1 = maxX - STAMP_SIZE, x2 = maxX + STAMP_SIZE;
                if(x1 < 0) x1 = 0;
                else if(x2 >= width) x2 = width-1;
                int y1 = maxY - STAMP_SIZE, y2 = maxY + STAMP_SIZE;
                if(y1 < 0) y1 = 0;
                else if(y2 >= height) y2 = height-1;
                UIImage *stamp = [self createUIImageWithWidth:(x2-x1+1) Height:(y2-y1+1) AtLeftEdge:x1 TopEdge:y1 FromRawData:rawImageBytes WithRawWidth:width RawHeight:height];
                [self.cosmicImages addObject:stamp];
            }
            
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

- (void) saveImageToFilesystem:(UIImage*)image {
    // Add this sub-image to our list of saved images
    NSURL *docsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *pathComponent = [NSString stringWithFormat:@"%@.png", [NSDate date]];
    NSURL *imageURL = [docsDirectory URLByAppendingPathComponent:pathComponent];
    NSError *writeError;
    [UIImagePNGRepresentation(image) writeToURL:imageURL options:NSDataWritingAtomic error:&writeError];
    if(VERBOSE) NSLog(@"Written To Filesystem at %@", imageURL);
    if(writeError) NSLog(@"Write to Filesystem Error: %@", writeError.userInfo);    
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
