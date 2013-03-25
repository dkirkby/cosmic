//
//  CosmicViewController.h
//  Cosmic
//
//  Created by David Kirkby on 3/11/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface CosmicViewController : UIViewController

@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;
@property (weak, nonatomic) IBOutlet UIButton *goButton;
@property (weak, nonatomic) IBOutlet UILabel *exposureCount;

@end
