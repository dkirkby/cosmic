//
//  CosmicCell.m
//  Cosmic
//
//  Created by Dylan Kirkby on 5/16/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import "CosmicCell.h"

@interface CosmicCell ()
@property (strong, nonatomic) UIImageView *cellImage;
@end

@implementation CosmicCell

- (UIImageView *)cellImage
{
    if(!_cellImage) _cellImage = [[UIImageView alloc] initWithFrame:self.bounds];
    return _cellImage;
}

- (void)setImage:(UIImage *)image
{
    self.cellImage.image = nil;
    self.cellImage.contentMode = UIViewContentModeScaleAspectFill;
    self.cellImage.image = image;
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
    [self addSubview:self.cellImage];
    self.cellImage.backgroundColor = [[UIColor blueColor] colorWithAlphaComponent:0.5];
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
