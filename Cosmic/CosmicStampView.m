//
//  CosmicStampView.m
//  Cosmic
//
//  Created by Dylan Kirkby on 5/20/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import "CosmicStampView.h"

@implementation CosmicStampView

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
