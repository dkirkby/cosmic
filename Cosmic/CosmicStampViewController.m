//
//  CosmicStampViewController.m
//  Cosmic
//
//  Created by Dylan Kirkby on 5/20/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import "CosmicStampViewController.h"

@interface CosmicStampViewController ()
@property (nonatomic) Stamp tempStamp;

@property (weak, nonatomic) IBOutlet CosmicStampView *cosmicStampView;
@property (weak, nonatomic) IBOutlet UILabel *timeLabel;
@property (weak, nonatomic) IBOutlet UILabel *coordinatesLabel;
@property (weak, nonatomic) IBOutlet UILabel *countLabel;
@end

@implementation CosmicStampViewController

#define WIDTH 2592
- (void)setStamp:(Stamp)stamp
{
    self.tempStamp = stamp;
}

- (void)viewDidLoad
{
    self.cosmicStampView.frame = CGRectMake(self.cosmicStampView.frame.origin.x, self.cosmicStampView.frame.origin.y, self.cosmicStampView.frame.size.width, self.cosmicStampView.frame.size.width);
    
    [self.cosmicStampView setStamp:self.tempStamp];
    self.timeLabel.text = [NSString stringWithFormat:@"%u ms", self.tempStamp.elapsedMSecs];
    self.coordinatesLabel.text = [NSString stringWithFormat:@"(%u,%u)", self.tempStamp.maxPixelIndex/WIDTH, self.tempStamp.maxPixelIndex%WIDTH];
    self.countLabel.text = [NSString stringWithFormat:@"%u", self.tempStamp.exposureCount];
}

@end
