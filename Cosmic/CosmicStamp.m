//
//  CosmicStamp.m
//  Cosmic
//
//  Created by Dylan Kirkby on 5/20/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import "CosmicStamp.h"

@implementation CosmicStamp

#pragma mark - Setters/Getters

- (uint8_t *)rgb
{
    //contents of returned array are undefined
    if(!_rgb) _rgb = malloc([[self class] rgbSize]);
    return _rgb;
}

+ (size_t)rgbSize
{
    return 3*(2*STAMP_SIZE+1)*(2*STAMP_SIZE+1);
}

@end
