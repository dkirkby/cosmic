//
//  CosmicBrain.h
//  Cosmic
//
//  Created by David Kirkby on 3/11/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CosmicBrain;

#define STAMP_SIZE 7

typedef struct {
    // milliseconds since program started, wraps around after 49.7 days
    uint32_t elapsedMSecs;
    // index = y*width+x of stamp's central pixel with largest R+2*G+B
    uint32_t maxPixelIndex;
    // exposure counter for this stamp (starting from zero)
    uint32_t exposureCount;
    // RGB byte data starting from sensor's top-right corner (with phone in portrait orientation)
    // and increasing fastest down the sensor.
    uint8_t rgb[3*(2*STAMP_SIZE+1)*(2*STAMP_SIZE+1)];
} Stamp;

@protocol CosmicBrainDelegate <NSObject>
- (void) setExposureCount:(int)count;
- (void) stampAdded;
@end

@interface CosmicBrain : NSObject

@property (strong, nonatomic) NSMutableArray *cosmicStamps;

@property(nonatomic,assign) id <CosmicBrainDelegate> brainDelegate;

- (void) initCapture;
- (void) beginCapture;
- (void) captureImage;

@end
