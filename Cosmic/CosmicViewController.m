//
//  CosmicViewController.m
//  Cosmic
//
//  Created by David Kirkby on 3/11/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import "CosmicViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "CosmicCell.h"

@interface CosmicViewController () <CosmicBrainDelegate, UIScrollViewDelegate, UICollectionViewDataSource>
@property (strong, nonatomic) CosmicBrain *brain;
@property (nonatomic) BOOL shouldTakeAnotherImage;

@property (weak, nonatomic) IBOutlet UICollectionView *collectionView;
@property (weak, nonatomic) IBOutlet UIButton *goButton;
@property (weak, nonatomic) IBOutlet UILabel *exposureCountLabel;
@end

@implementation CosmicViewController

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

#pragma mark - ViewController Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.collectionView.dataSource = self;
    [self.brain initCapture];
    [self.brain beginCapture];
    self.goButton.enabled = NO;
    self.exposureCountLabel.text = @"0";
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Target/Action

- (IBAction)goButtonPressed:(UIButton *)sender {
    NSLog(@"Taking Exposure");
    [self.brain captureImage];
    self.goButton.enabled = NO;
}

#pragma mark - CosmicBrainDelegate

- (void) setExposureCount:(int)count {
    self.exposureCountLabel.text = [NSString stringWithFormat:@"%d",count];
}

- (void)stampAdded
{
    Stamp buffer;
    NSValue *stampWrapper = [self.brain.cosmicStamps lastObject];
    if(stampWrapper){
        [stampWrapper getValue:&buffer];
        NSLog(@"Cosmic Stamp: %u", buffer.exposureCount);
        [self.collectionView reloadData];
    }
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.brain.cosmicStamps.count;
}

- (Stamp)stampForindexPath:(NSIndexPath *)indexPath
{
    NSValue *stampWrapper = self.brain.cosmicStamps[indexPath.item];
    if(stampWrapper){
        
        Stamp buffer;
        [stampWrapper getValue:&buffer];
        
        return buffer;
    }
    
    Stamp bad;
    return bad;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *reuseIdentifier = @"StampCell";
    CosmicCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:reuseIdentifier forIndexPath:indexPath];
    
    if(!cell) NSLog(@"Error: No Cell");
    
    [cell setStamp:[self stampForindexPath:indexPath]];
    
    return cell;
}

#pragma mark - Gesture Recognizers

#define FADE_TIME 0.25
#define MAX_OPACITY 0.85
- (IBAction)imageViewTapped:(UIGestureRecognizer *)gesture
{
    if(self.goButton.isHidden){
        //if buttons are already hidden, display buttons with animation
        [UIView animateWithDuration:FADE_TIME animations:^{
            self.goButton.alpha = MAX_OPACITY;
            self.exposureCountLabel.alpha = MAX_OPACITY;
            self.goButton.hidden = NO;
            self.exposureCountLabel.hidden = NO;
        }];
    } else {
        //if buttons are currently visible, hide buttons immediately
        if(!CGRectContainsPoint([self controlButtonArea], [gesture locationInView:self.view])){
            self.goButton.alpha = 0.0;
            self.exposureCountLabel.alpha = 0.0;
            self.goButton.hidden = YES;
            self.exposureCountLabel.hidden = YES;
        }
    }
}
           
- (CGRect)controlButtonArea{
    CGFloat x = self.goButton.frame.origin.x;
    CGFloat y = self.goButton.frame.origin.y;
    CGFloat width = self.goButton.frame.size.width + self.exposureCountLabel.frame.size.width;
    CGFloat height = self.goButton.frame.size.height;

    return CGRectMake(x, y, width, height);
}

- (IBAction)buttonSwipedDown:(UIGestureRecognizer *)gesture
{
    if(!self.goButton.isHidden){
        [UIView animateWithDuration:FADE_TIME delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState animations:^{
            [self moveFrameDown:self.goButton];
            [self moveFrameDown:self.exposureCountLabel];
        } completion:^(BOOL success){
            if(success){
                self.goButton.alpha = 0.0;
                self.exposureCountLabel.alpha = 0.0;
                self.goButton.hidden = YES;
                self.exposureCountLabel.hidden = YES;
                [self moveFrameUp:self.goButton];
                [self moveFrameUp:self.exposureCountLabel];
            }
        }];
    }
}

- (IBAction)buttonSwipedUp:(UIGestureRecognizer *)gesture
{    
    if(self.goButton.isHidden){
        [self moveFrameDown:self.goButton];
        [self moveFrameDown:self.exposureCountLabel];
        self.goButton.alpha = MAX_OPACITY;
        self.exposureCountLabel.alpha = MAX_OPACITY;
        self.goButton.hidden = NO;
        self.exposureCountLabel.hidden = NO;
        
        [UIView animateWithDuration:FADE_TIME delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            [self moveFrameUp:self.goButton];
            [self moveFrameUp:self.exposureCountLabel];
        } completion:nil];
    }
}

- (void)moveFrameDown:(UIView *)viewToMove
{
    viewToMove.frame = CGRectMake(viewToMove.frame.origin.x, viewToMove.frame.origin.y + viewToMove.frame.size.height, viewToMove.frame.size.width, viewToMove.frame.size.height);
}

- (void)moveFrameUp:(UIView *)viewToMove
{
    viewToMove.frame = CGRectMake(viewToMove.frame.origin.x, viewToMove.frame.origin.y - viewToMove.frame.size.height, viewToMove.frame.size.width, viewToMove.frame.size.height);
}

@end
