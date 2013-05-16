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

- (IBAction)refresh {
    [self.collectionView reloadData];
}

#pragma mark - CosmicBrainDelegate

- (void) setExposureCount:(int)count {
    NSLog(@"the count is now %d",count);
    self.exposureCountLabel.text = [NSString stringWithFormat:@"%d",count];
}

- (void) addAnImage:(UIImage *)image {
    //[self.cosmicImages addObject:image];
    [self.collectionView reloadData];
}

- (void)imageAdded
{
    [self.collectionView reloadData];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.brain.cosmicImages.count;
}

- (UIImage *)imageForIndexPath:(NSIndexPath *)indexPath
{
    return self.brain.cosmicImages[indexPath.item];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *reuseIdentifier = @"StampCell";
    CosmicCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:reuseIdentifier forIndexPath:indexPath];
    NSLog(@"Index Path: %@", indexPath);
    
    if(!cell) NSLog(@"Error: No Cell");
    
    [cell setImage:[self imageForIndexPath:indexPath]];
    
    return cell;
}

#pragma mark - Gesture Recognizers

#define FADE_TIME 0.25
#define MAX_OPACITY 0.85
- (IBAction)imageViewTapped:(UIGestureRecognizer *)gesture
{
    if(self.goButton.hidden){
        //display buttons with animation
        [UIView animateWithDuration:FADE_TIME animations:^{
            self.goButton.alpha = MAX_OPACITY;
            self.exposureCountLabel.alpha = MAX_OPACITY;
            self.goButton.hidden = FALSE;
            self.exposureCountLabel.hidden = FALSE;
        }];
    } else {
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
