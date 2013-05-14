//
//  CosmicViewController.h
//  Cosmic
//
//  Created by David Kirkby on 3/11/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import <UIKit/UIKit.h>

#include "CosmicBrain.h"

@interface CosmicViewController : UIViewController
- (IBAction)imageViewTapped:(UIGestureRecognizer *)gesture;
- (IBAction)buttonSwipedDown:(UIGestureRecognizer *)gesture;
@end
