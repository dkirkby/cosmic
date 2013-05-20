//
//  CosmicStampViewController.h
//  Cosmic
//
//  Created by Dylan Kirkby on 5/20/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CosmicStampView.h"

@interface CosmicStampViewController : UIViewController
@property (weak, nonatomic) IBOutlet CosmicStampView *cosmicStampView;
@property (weak, nonatomic) IBOutlet UILabel *timeLabel;
@property (weak, nonatomic) IBOutlet UILabel *coordinatesLabel;
@property (weak, nonatomic) IBOutlet UILabel *countLabel;
@end
