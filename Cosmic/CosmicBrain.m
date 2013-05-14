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
    for(AVCaptureDevice *device in cameras) {
        NSLog(@"found '%@'",device.localizedName);
    }
    // Use the first available input device (for now)
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:[cameras objectAtIndex:0] error:&error];
    if(!input) {
        NSLog(@"PANIC: no media input");
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
}

- (void) captureImage {
    NSLog(@"capturing image...");
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
        
        UIGraphicsBeginImageContext(CGSizeMake(width,height));
        CGContextRef c = UIGraphicsGetCurrentContext();
        unsigned char* data = CGBitmapContextGetData(c);
        if (data != NULL) {
            for(int y = 0; y < height; y++) {
                for(int x = 0; x < width; x++) {
                    int offset = bytesPerPixel*((width*y)+x);
                    data[offset] = rawImageBytes[offset];     // R
                    data[offset+1] = rawImageBytes[offset+1]; // G
                    data[offset+2] = rawImageBytes[offset+2]; // B
                    data[offset+3] = rawImageBytes[offset+3]; // A
                }
            }
        }
        self.lastImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        // All done with the image buffer so release it now
        CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
        
        // Update our UI thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self gotImage];
        });
    }];
}

- (void) gotImage {
    self.exposureCount++;
    NSLog(@"Got exposure #%d",self.exposureCount);
    [self.brainDelegate setExposureCount:self.exposureCount];
    [self.brainDelegate displayAnImage:self.lastImage];
}

@end
