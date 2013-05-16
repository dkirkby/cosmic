//
//  CosmicCell.m
//  Cosmic
//
//  Created by Dylan Kirkby on 5/16/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import "CosmicCell.h"

@interface CosmicCell ()
@property (strong, nonatomic) UILabel *cellLabel;
@end

@implementation CosmicCell
@synthesize title = _title;

- (UILabel *)cellLabel
{
    if(!_cellLabel) _cellLabel = [[UILabel alloc] initWithFrame:self.bounds];
    return _cellLabel;
}

#define DEFAULT_LABEL_TEXT @"Stamp";
- (NSString *)title
{
    if(!_title) _title = DEFAULT_LABEL_TEXT;
    return _title;
}

- (void)setTitle:(NSString *)title
{
    _title = title;
    self.cellLabel.text = title;
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
    [self addSubview:self.cellLabel];
    self.cellLabel.text = self.title;
    self.cellLabel.backgroundColor = [UIColor blueColor];
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
