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
    // Look for an input device
    NSArray *cameras=[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for(AVCaptureDevice *device in cameras) {
        NSLog(@"found %@",device.localizedName);
    }
    // Set the input device
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:[cameras objectAtIndex:0] error:&error];
    if(!input) {
        NSLog(@"PANIC: no media input");
    }
    else {
        [self.captureSession addInput:input];
    }
}

- (void) captureImage {
    NSLog(@"capturing image...");
}

@end
