//
//  CosmicCell.m
//  Cosmic
//
//  Created by Dylan Kirkby on 5/16/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import "CosmicCell.h"

@interface CosmicCell ()
@property (strong, nonatomic) CosmicStampView *cosmicStampView;
@end

@implementation CosmicCell

- (CosmicStampView *)cosmicStampView
{
    if(!_cosmicStampView) _cosmicStampView = [[CosmicStampView alloc] initWithFrame:self.bounds];
    return _cosmicStampView;
}

- (void)setStamp:(Stamp *)stamp
{
    self.cosmicStampView.stamp = nil;
    self.cosmicStampView.stamp = stamp;
}

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
    [self addSubview:self.cosmicStampView];
    self.cosmicStampView.backgroundColor = [[UIColor blueColor] colorWithAlphaComponent:0.5];
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

@end
