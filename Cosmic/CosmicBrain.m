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

@interface CosmicBrain ()

@property AVCaptureDevice *bestDevice;
@property AVCaptureSession *captureSession;
@property AVCaptureStillImageOutput *cameraOutput;
@property enum { IDLE, BEGINNING, RUNNING } state;
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
        
        NSMutableArray *images = [[NSMutableArray alloc] init];
        // Add 0,1,or 2 sub-images for testing
        int nImages = self.exposureCount%3;
        for(int count = 0; count < nImages; ++count) {
            // Grab a sub-image
            UIImage *image = [self createUIImageWithWidth:256 Height:256 AtLeftEdge:800+128*count TopEdge:800+128*count FromRawData:rawImageBytes WithRawWidth:width RawHeight:height];
            // Add this sub-image to our list of saved images
            [images addObject:image];
        }
        if(VERBOSE) NSLog(@"Added %d images from this exposure.",images.count);
        
        // All done with the image buffer so release it now
        CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
        
        // The first image is for calibration only.
        if(self.state == BEGINNING) {
            self.state = RUNNING;
        }
        
        self.exposureCount++;

        // Update our delegate on the UI thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.brainDelegate setExposureCount:self.exposureCount];
            for(int index = 0; index < images.count; ++index) {
                [self.cosmicImages addObject:[images objectAtIndex:index]];
            }
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
        size_t rawOffset = y*bytesPerRawRow + leftEdge;
        memcpy(imgData+imgOffset, rawData+rawOffset, bytesPerImgRow);
    }
    
    //quick fix to sideways image problem
    UIImage *image = [[UIImage alloc] initWithCGImage:UIGraphicsGetImageFromCurrentImageContext().CGImage scale:1.0 orientation:UIImageOrientationRight];
 
    UIGraphicsEndImageContext();
    
    return image;
}

@end
