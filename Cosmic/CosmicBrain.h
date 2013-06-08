//
//  CosmicBrain.h
//  Cosmic
//
//  Created by David Kirkby on 3/11/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CosmicBrain;

@protocol CosmicBrainDelegate <NSObject>
- (void) setExposureCount:(int)count;
- (void) stampAdded;
@end

@interface CosmicBrain : NSObject

@property (strong, nonatomic) NSMutableArray *cosmicStamps;

@property(nonatomic,assign) id <CosmicBrainDelegate> brainDelegate;

- (void) initCapture;
- (void) beginCalibration;
- (void) endCalibration;
- (void) beginRun;
- (void) beginCapture;

@end
