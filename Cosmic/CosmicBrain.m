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
    self.captureSession = [[AVCaptureSession alloc] init];
}

- (void) captureImage {
    NSLog(@"capturing image...");
}

@end
