//
//  CosmicStampView.m
//  Cosmic
//
//  Created by Dylan Kirkby on 5/20/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import "CosmicStampView.h"
#define BORDER YES

@interface CosmicStampView ()
@property (nonatomic) UInt8 maxColor;
@end

@implementation CosmicStampView

#pragma mark - Setters/Getters

- (void)setStamp:(CosmicStamp *)stamp
{
    _stamp = stamp;
    [self pruneStamp];
    [self setNeedsDisplay];
}

#pragma mark - Initialization

- (void)awakeFromNib
{
    [self setup];
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup
{
    //do nothing
}

#pragma mark - Pruning

- (void)pruneStamp
{
    int stampWidthInPixels = (2*STAMP_SIZE+1);
    int stampHeightInPixels = (2*STAMP_SIZE+1);
    
    UInt8 *rgbPointer = self.stamp.rgb;
    
    self.maxColor = 0;
    for(int x=0; x<stampHeightInPixels; ++x){
        for(int y=0; y<stampWidthInPixels; ++y){
            UInt8 red = *rgbPointer++;
            UInt8 green = *rgbPointer++;
            UInt8 blue = *rgbPointer++;
            if(red > _maxColor)_maxColor = red;
            if(green > _maxColor)_maxColor = green;
            if(blue > _maxColor)_maxColor = blue;

        }
    }
}

#pragma mark - Custom Drawing

// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
    int stampWidthInPixels = (2*STAMP_SIZE+1);
    int stampHeightInPixels = (2*STAMP_SIZE+1);
    
    UInt8 *rgbPointer = self.stamp.rgb;
        
    for(int x=0; x<stampHeightInPixels; ++x){
        for(int y=0; y<stampWidthInPixels; ++y){
            UInt8 red = *rgbPointer++;
            UInt8 green = *rgbPointer++;
            UInt8 blue = *rgbPointer++;
            [self drawPixelWithX:x withY:y andR:red andG:green andB:blue];
        }
    }
}

- (void) drawPixelWithX:(int)x withY:(int)y andR:(UInt8)red andG:(UInt8)green andB:(UInt8)blue
{
    //Note: will distort if bounds are not square
    CGFloat max_x = self.bounds.origin.x + self.bounds.size.width;
    CGFloat max_y = self.bounds.origin.y + self.bounds.size.height;
    
    int stampWidthInPixels = (2*STAMP_SIZE+1);
    int stampHeightInPixels = (2*STAMP_SIZE+1);
    
    CGFloat pixelWidth = max_x / stampWidthInPixels;
    CGFloat pixelHeight = max_y / stampHeightInPixels;
    
    CGRect pixel = CGRectMake(x*pixelWidth, y*pixelHeight, pixelWidth, pixelHeight);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [[UIColor colorWithRed:red/(CGFloat)self.maxColor green:green/(CGFloat)self.maxColor blue:blue/(CGFloat)self.maxColor alpha:1.0] setFill];
    CGContextFillRect(context, pixel);
    [[UIColor darkGrayColor] setStroke];
    if(BORDER)CGContextStrokeRect(context, pixel);
}

@end
