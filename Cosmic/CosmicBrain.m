//
//  CosmicBrain.m
//  Cosmic
//
//  Created by David Kirkby on 3/11/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import "CosmicBrain.h"
#import <AVFoundation/AVFoundation.h>

@interface CosmicBrain ()
@property AVCaptureSession *captureSession;
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
    // Set the output device
    AVCaptureStillImageOutput *output = [[AVCaptureStillImageOutput alloc] init];
    [self.captureSession addOutput:output];
}

- (void) captureImage {
    NSLog(@"capturing image...");
}

@end
