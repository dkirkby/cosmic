//
//  CosmicViewController.m
//  Cosmic
//
//  Created by David Kirkby on 3/11/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import "CosmicViewController.h"
#import <AVFoundation/AVFoundation.h>

//We dont need to publicly declare we implement this delegate.
//We also dont need to publicly declare our UI outlets, they can be private too.
@interface CosmicViewController () <CosmicBrainDelegate, UIScrollViewDelegate>
@property (nonatomic,strong) CosmicBrain *brain;
@property (nonatomic,strong) UIImage *displayImage;

@property (weak, nonatomic) IBOutlet UIImageView *imageOutlet;
@property (weak, nonatomic) IBOutlet UIButton *goButton;
@property (weak, nonatomic) IBOutlet UILabel *exposureCountLabel;
@property (weak, nonatomic) IBOutlet UIView *tappableView;
@end

@implementation CosmicViewController
@synthesize displayImage = _displayImage;   //need to synthezize b/c overriding setter AND getter

#pragma mark - Setters/Getters

- (CosmicBrain *)brain
{
    if(!_brain) {
        // Lazy instantiation
        _brain = [[CosmicBrain alloc] init];
        // Register ourselves as a brain delegate
        _brain.brainDelegate = self;
    }
    return _brain;
}

- (UIImage *)displayImage
{
    if(!_displayImage) _displayImage = [[UIImage alloc] init];
    return _displayImage;
}

- (void)setDisplayImage:(UIImage *)displayImage
{
    _displayImage = displayImage;
    
    self.imageOutlet.image = displayImage;
    self.imageOutlet.contentMode = UIViewContentModeScaleAspectFill; //Fit or Fill is a preference
}

#pragma mark - ViewController Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.brain initCapture];
    [self.brain beginCapture];
    self.exposureCountLabel.text = @"0";
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Target/Action

- (IBAction)goButtonPressed:(UIButton *)sender {
    NSLog(@"go!");
    [self.brain captureImage];
}

#pragma mark - CosmicBrainDelegate

- (void) setExposureCount:(int)count {
    NSLog(@"the count is now %d",count);
    self.exposureCountLabel.text = [NSString stringWithFormat:@"%d",count];
}

- (void) addAnImage:(UIImage *)image {
    self.displayImage = image;
}

#pragma mark - Gesture Recognizers

#define FADE_TIME 0.25
#define MAX_OPACITY 0.85
- (IBAction)imageViewTapped:(UIGestureRecognizer *)gesture
{
    if(self.goButton.hidden){
        self.tappableView.frame = CGRectMake(0, 0, self.tappableView.frame.size.width, self.tappableView.frame.size.height - self.goButton.frame.size.height);
        //display buttons with animation
        [UIView animateWithDuration:FADE_TIME animations:^{
            self.goButton.alpha = MAX_OPACITY;
            self.exposureCountLabel.alpha = MAX_OPACITY;
            self.goButton.hidden = FALSE;
            self.exposureCountLabel.hidden = FALSE;
        }];
    } else {
        self.tappableView.frame = CGRectMake(0, 0, self.tappableView.frame.size.width, self.tappableView.frame.size.height + self.goButton.frame.size.height);
        //hide buttons immediately
        self.goButton.alpha = 0.0;
        self.exposureCountLabel.alpha = 0.0;
        self.goButton.hidden = TRUE;
        self.exposureCountLabel.hidden = TRUE;
    }
}

- (IBAction)buttonSwipedDown:(UIGestureRecognizer *)gesture
{
    /*
    NSLog(@"Swipe");
    [UIView animateWithDuration:FADE_TIME delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.goButton.frame = CGRectMake(self.goButton.frame.origin.x, self.goButton.frame.origin.y + self.goButton.frame.size.height, self.goButton.frame.size.width, self.goButton.frame.size.height);
        self.exposureCountLabel.frame = CGRectMake(self.exposureCountLabel.frame.origin.x, self.exposureCountLabel.frame.origin.y + self.exposureCountLabel.frame.size.height, self.exposureCountLabel.frame.size.width, self.exposureCountLabel.frame.size.height);
    } completion:nil];
     */
}

@end
