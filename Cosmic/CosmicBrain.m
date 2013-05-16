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

@interface CosmicBrain ()
@property AVCaptureDevice *bestDevice;
@property AVCaptureSession *captureSession;
@property AVCaptureStillImageOutput *cameraOutput;
- (void) gotImage;
@end

@implementation CosmicBrain

- (void) initCapture {
    NSLog(@"initializing capture...");
    // Initialize a session with the photo preset
    self.captureSession = [[AVCaptureSession alloc] init];
    if([self.captureSession canSetSessionPreset:AVCaptureSessionPresetPhoto]) {
        self.captureSession.sessionPreset = AVCaptureSessionPresetPhoto;
    }
    else {
        NSLog(@"Failed to set the photo session preset!");
    }
    // Look for a suitable input device (we look for "video" here since there is no separate still image type)
    NSArray *cameras=[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    if(cameras.count == 0) {
        NSLog(@"No video devices available.");
        return;
    }
    self.bestDevice = nil;
    for(AVCaptureDevice *device in cameras) {
        // Look up this camera's capabilities
        BOOL exposureLock = [device isExposureModeSupported:AVCaptureExposureModeLocked];
        BOOL focusLock = [device isFocusModeSupported:AVCaptureFocusModeLocked];
        NSLog(@"Found '%@' (exposure lock? %s; focus lock? %s)",device.localizedName,
              (exposureLock ? "yes":"no"),(focusLock ? "yes":"no"));
        // Is this the best so far?
        if(nil == self.bestDevice && exposureLock && focusLock) self.bestDevice = device;
    }
    if(nil == self.bestDevice) {
        NSLog(@"PANIC: no suitable camera device available!");
        return;
    }
    NSLog(@"Using '%@' to capture images.",self.bestDevice.localizedName);
    // Configure a capture session using the best device.
    NSError *error = nil;
    AVCaptureDeviceInput *input =
        [AVCaptureDeviceInput deviceInputWithDevice:self.bestDevice error:&error];
    if(!input) {
        NSLog(@"PANIC: failed to configure device input!");
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

- (void) beginCapture {
    self.state = BEGINNING;
    NSLog(@"begin capture...");
    // Try to lock the exposure and focus for the best device.
    NSError *error = nil;
    if([self.bestDevice lockForConfiguration:&error]) {
        CGPoint center = CGPointMake(0.5,0.5);
        if([self.bestDevice isFocusPointOfInterestSupported]) {
            [self.bestDevice setFocusPointOfInterest:center];
            NSLog(@"Set focus point of interest.");
        }
        if([self.bestDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
            [self.bestDevice setFocusMode:AVCaptureFocusModeAutoFocus];
            NSLog(@"Autofocus successful.");
        }
        else if([self.bestDevice isFocusModeSupported:AVCaptureFocusModeLocked]) {
            [self.bestDevice setFocusMode:AVCaptureFocusModeLocked];
            NSLog(@"Focus lock successful.");
        }
        if([self.bestDevice isExposurePointOfInterestSupported]) {
            [self.bestDevice setExposurePointOfInterest:center];
            NSLog(@"Set exposure point of interest.");
        }
        if([self.bestDevice isExposureModeSupported:AVCaptureExposureModeAutoExpose]) {
            [self.bestDevice setExposureMode:AVCaptureExposureModeAutoExpose];
            NSLog(@"Autoexposure successful.");
        }
        else if([self.bestDevice isExposureModeSupported:AVCaptureExposureModeLocked]) {
            [self.bestDevice setExposureMode:AVCaptureExposureModeLocked];
            NSLog(@"Exposure lock successful.");
        }
        [self.bestDevice unlockForConfiguration];
        // Capture an initial calibration image
        [self captureImage];
    }
    else {
        NSLog(@"PANIC: cannot lock device for exposure and focus configuration.");
        return;
    }
}

- (void) captureImage {
    if(self.state == IDLE) {
        NSLog(@"Cannot captureImage before beginImage.");
        return;
    }
    NSLog(@"capturing image in state %d...",self.state);
    [self.cameraOutput captureStillImageAsynchronouslyFromConnection:[[self.cameraOutput connections] objectAtIndex:0] completionHandler:^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
        
        // Lookup this frame's properties
        CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(imageSampleBuffer);
        CVPixelBufferLockBaseAddress(cameraFrame, 0);
        size_t width = CVPixelBufferGetWidth(cameraFrame);
        size_t height = CVPixelBufferGetHeight(cameraFrame);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(cameraFrame);
        int bytesPerPixel = bytesPerRow/width;
        NSLog(@"processing raw data %lu x %lu with %d bytes per pixel",width,height,bytesPerPixel);

        // Lookup this image's metadata
        CFDictionaryRef exifAttachments = CMGetAttachment(imageSampleBuffer, kCGImagePropertyExifDictionary, NULL);
        if (exifAttachments) {
            // Do something with the attachments.
            NSLog(@"attachements: %@", exifAttachments);
        }
        else {
            NSLog(@"no attachments");
        }
        CFNumberRef shutter = CMGetAttachment( imageSampleBuffer, kCGImagePropertyExifShutterSpeedValue, NULL);
        NSLog(@"\n shuttervalue : %@",shutter);

        // Look at the actual image data
        GLubyte *rawImageBytes = CVPixelBufferGetBaseAddress(cameraFrame);
        
        self.lastImage = [self createUIImageWithWidth:width AndHeight:height FromRawData:rawImageBytes WithRawWidth:width AndRawHeight:height];
            
        // All done with the image buffer so release it now
        CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
        
        // The first image is for calibration only.
        if(self.state == BEGINNING) {
            self.state = RUNNING;
        }
        
        // Update our UI thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self gotImage];
        });
    }];
}

- (UIImage*) createUIImageWithWidth:(int)imageWidth AndHeight:(int)imageHeight FromRawData:(unsigned char *)rawData WithRawWidth:(int)rawWidth AndRawHeight:(int)rawHeight {

    UIGraphicsBeginImageContext(CGSizeMake(imageWidth,imageHeight));
    CGContextRef c = UIGraphicsGetCurrentContext();
    unsigned char* data = CGBitmapContextGetData(c);

    int bytesPerPixel = 4;
    for(int y = 0; y < rawHeight; y++) {
        for(int x = 0; x < rawWidth; x++) {
            int offset = bytesPerPixel*((rawWidth*y)+x);
            data[offset] = rawData[offset];     // R
            data[offset+1] = rawData[offset+1]; // G
            data[offset+2] = rawData[offset+2]; // B
            data[offset+3] = rawData[offset+3]; // A
        }
    }
    
    //quick fix to sideways image problem
    UIImage *image = [[UIImage alloc] initWithCGImage:UIGraphicsGetImageFromCurrentImageContext().CGImage scale:1.0 orientation:UIImageOrientationRight];
    
    UIGraphicsEndImageContext();
    
    return image;
}

- (void) gotImage {
    self.exposureCount++;
    NSLog(@"Got exposure #%d",self.exposureCount);
    [self.brainDelegate setExposureCount:self.exposureCount];
    [self.brainDelegate displayAnImage:self.lastImage];
}

@end
