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

@property (nonatomic) uint32_t elapsedMSecs;
@property (nonatomic) uint32_t maxPixelIndex;
@property (nonatomic) uint32_t exposureCount;
@property (nonatomic) uint8_t *rgb;

+ (size_t)rgbSize;
@end
