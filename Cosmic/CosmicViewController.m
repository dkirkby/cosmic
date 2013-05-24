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
#import "CosmicStampViewController.h"

@interface CosmicViewController () <CosmicBrainDelegate, UIScrollViewDelegate, UICollectionViewDataSource>
@property (strong, nonatomic) CosmicBrain *brain;
@property (weak, nonatomic) IBOutlet UICollectionView *collectionView;
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
        
    self.navigationController.navigationBar.tintColor = [UIColor blackColor];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Segue

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    static NSString *identifier = @"showCosmicStamp";
    if([segue.identifier isEqualToString:identifier]){
        if([segue.destinationViewController isKindOfClass:[CosmicStampViewController class]]){
            CosmicStamp *stamp = [self stampForindexPath:[self.collectionView indexPathForCell:sender]];
            CosmicStampViewController *csvc = (CosmicStampViewController *)segue.destinationViewController;
            [csvc setStamp:stamp];
        }
    }
}

#pragma mark - CosmicBrainDelegate

- (void) setExposureCount:(int)count {
    static NSString *vcTitle =  @"Cosmic Rays";
    //display count
    self.title = [vcTitle stringByAppendingFormat:@"    %i", count];
}

- (void)stampAdded
{
    NSArray *indexPaths = @[[NSIndexPath indexPathForItem:self.brain.cosmicStamps.count-1 inSection:0]];
    [self.collectionView insertItemsAtIndexPaths:indexPaths];
    //see if it auto reloads
    //[self.collectionView reloadItemsAtIndexPaths:indexPaths];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.brain.cosmicStamps.count;
}

- (CosmicStamp *)stampForindexPath:(NSIndexPath *)indexPath
{
    return self.brain.cosmicStamps[indexPath.item];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *reuseIdentifier = @"StampCell";
    CosmicCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:reuseIdentifier forIndexPath:indexPath];
    
    if(!cell) NSLog(@"Error: No Cell");
    
    [cell setStamp:[self stampForindexPath:indexPath]];
    
    return cell;
}

@end
