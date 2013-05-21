//
//  CosmicStamp.h
//  Cosmic
//
//  Created by Dylan Kirkby on 5/20/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import <Foundation/Foundation.h>

#define STAMP_SIZE 7

@interface CosmicStamp : NSObject
/*
 // milliseconds since program started, wraps around after 49.7 days
 uint32_t elapsedMSecs;
 // index = y*width+x of stamp's central pixel with largest R+2*G+B
 uint32_t maxPixelIndex;
 // exposure counter for this stamp (starting from zero)
 uint32_t exposureCount;
 // RGB byte data starting from sensor's top-right corner (with phone in portrait orientation)
 // and increasing fastest down the sensor.
 uint8_t rgb[3*(2*STAMP_SIZE+1)*(2*STAMP_SIZE+1)];
 */

@property (nonatomic) uint32_t elapsedMSecs;
@property (nonatomic) uint32_t maxPixelIndex;
@property (nonatomic) uint32_t exposureCount;
@property (nonatomic) uint8_t *rgb;

+ (size_t)rgbSize;
@end
