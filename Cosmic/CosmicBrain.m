//
//  CosmicBrain.m
//  Cosmic
//
//  Created by David Kirkby on 3/11/13.
//  Copyright (c) 2013 David Kirkby. All rights reserved.
//

#import "CosmicBrain.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>

#define VERBOSE NO

#define MIN_INTENSITY 64
#define MAX_REPEATS 4

typedef enum {
    IDLE,
    BEGINNING,
    RUNNING
} CosmicState;

@interface CosmicBrain () {
    unsigned char *_pixelCount;
    NSDate *_beginAt;
    NSTimeInterval _captureElapsed;
    Stamp *_theStamp;
}

@property(strong,nonatomic) AVCaptureDevice *bestDevice;
@property(strong,nonatomic) AVCaptureSession *captureSession;
@property(strong,nonatomic) AVCaptureStillImageOutput *cameraOutput;
@property CosmicState state;
@property int exposureCount, saveCount;
@property(strong,nonatomic) NSDateFormatter *timestampFormatter;

@end

@implementation CosmicBrain

#pragma mark - Setters/Getters

- (NSMutableArray *)cosmicStamps
{
    if(!_cosmicStamps) _cosmicStamps = [[NSMutableArray alloc] init];
    return _cosmicStamps;
}

- (NSMutableArray *)cosmicStampPointers
{
    if(!_cosmicStampPointers) _cosmicStampPointers = [[NSMutableArray alloc] init];
    return _cosmicStampPointers;
}

- (NSDateFormatter*)timestampFormatter
{
    if(!_timestampFormatter) {
        _timestampFormatter = [[NSDateFormatter alloc] init];
        [_timestampFormatter setDateFormat:@"YY-MM-dd-HH-mm-ss-SSS"];
    }
    return _timestampFormatter;
}

#pragma mark - Initialization

- (void) initCapture {
    if(VERBOSE) NSLog(@"initializing capture...");
    // Initialize a session with the photo preset
    self.captureSession = [[AVCaptureSession alloc] init];
    if([self.captureSession canSetSessionPreset:AVCaptureSessionPresetPhoto]) {
        self.captureSession.sessionPreset = AVCaptureSessionPresetPhoto;
    }
    else {
        if(VERBOSE) NSLog(@"Failed to set the photo session preset!");
    }
    // Look for a suitable input device (we look for "video" here since there is no separate still image type)
    NSArray *cameras=[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    if(cameras.count == 0) {
        if(VERBOSE) NSLog(@"No video devices available.");
        return;
    }
    self.bestDevice = nil;
    for(AVCaptureDevice *device in cameras) {
        // Look up this camera's capabilities
        BOOL exposureLock = [device isExposureModeSupported:AVCaptureExposureModeLocked];
        BOOL focusLock = [device isFocusModeSupported:AVCaptureFocusModeLocked];
        NSLog(@"Found '%@' (exposure lock? %s; focus lock? %s)",device.localizedName,
              (exposureLock ? "yes":"no"),(focusLock ? "yes":"no"));
        // Is this the best so far?
        if(!self.bestDevice && exposureLock) self.bestDevice = device;
    }
    if(nil == self.bestDevice) {
        NSLog(@"PANIC: no suitable camera device available!");
        return;
    }
    NSLog(@"Using '%@' to capture images.",self.bestDevice.localizedName);
    // Configure a capture session using the best device.
    NSError *error = nil;
    AVCaptureDeviceInput *input =
        [AVCaptureDeviceInput deviceInputWithDevice:self.bestDevice error:&error];
    if(!input) {
        NSLog(@"PANIC: failed to configure device input!");
        return;
    }
    [self.captureSession addInput:input];
    // Configure and set the output device
    self.cameraOutput = [[AVCaptureStillImageOutput alloc] init];
    // perhaps kCVPixelFormatType_32ARGB is faster?
    // http://stackoverflow.com/questions/14383932/convert-cmsamplebufferref-to-uiimage
    NSDictionary *outputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA],
                                    (id)kCVPixelBufferPixelFormatTypeKey,
                                    nil];
    [self.cameraOutput setOutputSettings:outputSettings];
    [self.captureSession addOutput:self.cameraOutput];
    // Start the session running now
    [self.captureSession startRunning];
    // Initialize our state
    self.exposureCount = 0;
    self.state = IDLE;
}

#pragma mark - Initial Focus/Exposure Locking

- (void) beginCapture {
    NSLog(@"begin capture...");
    // Try to lock the exposure and focus for the best device.
    NSError *error = nil;
    if([self.bestDevice lockForConfiguration:&error]) {
        CGPoint center = CGPointMake(0.5,0.5);
        if([self.bestDevice isFocusPointOfInterestSupported]) {
            [self.bestDevice setFocusPointOfInterest:center];
            NSLog(@"Set focus point of interest.");
        }
        if([self.bestDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
            [self.bestDevice setFocusMode:AVCaptureFocusModeAutoFocus];
            NSLog(@"Autofocus successful.");
        }
        else if([self.bestDevice isFocusModeSupported:AVCaptureFocusModeLocked]) {
            [self.bestDevice setFocusMode:AVCaptureFocusModeLocked];
            NSLog(@"Focus lock successful.");
        }
        if([self.bestDevice isExposurePointOfInterestSupported]) {
            [self.bestDevice setExposurePointOfInterest:center];
            NSLog(@"Set exposure point of interest.");
        }
        if([self.bestDevice isExposureModeSupported:AVCaptureExposureModeAutoExpose]) {
            [self.bestDevice setExposureMode:AVCaptureExposureModeAutoExpose];
            NSLog(@"Autoexposure successful.");
        }
        else if([self.bestDevice isExposureModeSupported:AVCaptureExposureModeLocked]) {
            [self.bestDevice setExposureMode:AVCaptureExposureModeLocked];
            NSLog(@"Exposure lock successful.");
        }
        [self.bestDevice unlockForConfiguration];
        // Initialize our state
        self.state = BEGINNING;
        self.exposureCount = self.saveCount = 0;
        // Capture an initial calibration image
        [self captureImage];
    }
    else {
        NSLog(@"PANIC: cannot lock device for exposure and focus configuration.");
        return;
    }
}

#pragma mark - Capture

- (void) captureImage {
    if(self.state == IDLE) {
        NSLog(@"Cannot captureImage before beginImage.");
        return;
    }
    if(VERBOSE) NSLog(@"capturing image in state %d...",self.state);
    NSDate *startAt = [[NSDate alloc] init];
    [self.cameraOutput captureStillImageAsynchronouslyFromConnection:[[self.cameraOutput connections] objectAtIndex:0] completionHandler:^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
        
        // Get a timestamp for this capture
        NSDate *timestamp = [[NSDate alloc] init];

        // Keep track of the elapsed time in the capture routine
        _captureElapsed += [timestamp timeIntervalSinceDate:startAt];
        
        // Lookup this frame's properties
        CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(imageSampleBuffer);
        CVPixelBufferLockBaseAddress(cameraFrame, 0);
        size_t width = CVPixelBufferGetWidth(cameraFrame);
        size_t height = CVPixelBufferGetHeight(cameraFrame);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(cameraFrame);
        int bytesPerPixel = bytesPerRow/width;
        if(VERBOSE) NSLog(@"processing raw data %lu x %lu with %d bytes per pixel",width,height,bytesPerPixel);

        // Print out exposure metdata first time only
        if(self.state == RUNNING && self.exposureCount == 0) {
            CFDictionaryRef exifAttachments = CMGetAttachment(imageSampleBuffer, kCGImagePropertyExifDictionary, NULL);
            if (exifAttachments) {
                // Do something with the attachments.
                NSLog(@"attachements: %@", exifAttachments);
            }
            else {
                NSLog(@"no attachments");
            }
        }
        
        // Look at the actual image data. Each pixel is stored as four bytes. When accessed
        // as an unsigned int, the bytes are packed as (A << 24) | (B << 16) | (G << 8) | R.
        // The first pixel in the buffer corresponds to the top-right corner of the sensor
        // (when the device is held in its normal portrait orientation). Pixels increase
        // fastest along the "width", which actually moves down in the image from the top-right
        // corner. After each width pixels, the image data moves down one row, or left in the
        // sensor. The last pixel corresponds to the bottom-left corner of the sensor.
        GLubyte *rawImageBytes = CVPixelBufferGetBaseAddress(cameraFrame);

        if(self.state == BEGINNING) {
            // The first image is for locking focus and exposure only.
            // Now that we know the image dimensions, initialize an array to count how often each pixel
            // is selected as the maximum intensity in an exposure.
            if(_pixelCount) free(_pixelCount);
            int countSize = sizeof(unsigned char)*width*height;
            _pixelCount = malloc(countSize);
            bzero(_pixelCount,countSize);
            // Allocate the stamp buffer we will use
            if(!_theStamp) free(_theStamp);
            _theStamp = malloc(sizeof(Stamp));
            NSLog(@"Initialized for %ld x %ld images and %d x %d stamps (%ld bytes)",width,height,2*STAMP_SIZE+1,2*STAMP_SIZE+1,sizeof(Stamp));
            _beginAt = [timestamp copy];
            _captureElapsed = self.saveCount = 0;
            self.state = RUNNING;
        }
        else { // RUNNING
            // Loop over raw pixels to find the pixel with the largest intensity r+2*g+b
            unsigned int maxIntensity = MIN_INTENSITY;
            unsigned maxIndex = width*height, lastIndex = width*height, index = 0;
            unsigned int *bufptr = (unsigned int *)rawImageBytes;
            unsigned char *countPtr = _pixelCount;
            while(index < lastIndex) {
                // get the next 32-bit word of pixel data and advance our buffer pointer
                unsigned int val = *bufptr++;
                // skip hot pixels
                if(*countPtr++ < MAX_REPEATS) {
                    // val = (A << 24) | (B << 16) | (G << 8) | R
                    // we only shift G component by 7 so that it gets multiplied by 2
                    unsigned int intensity = ((val&0xff0000) >> 16) + ((val&0xff00) >> 7) + (val&0xff);
                    if(intensity > maxIntensity) {
                        maxIntensity = intensity;
                        maxIndex = index;
                    }
                }
                index++;
            }
            // Did we find a candidate in this exposure?
            if(maxIndex != lastIndex) {
                
                // Update our counts for this pixel
                _pixelCount[maxIndex]++;
                
                // Convert the candidate index back to (x,y) coordinates in the raw image
                int maxX = maxIndex%width;
                int maxY = maxIndex/width;

                // Calculate stamp bounds [x1,y1]-[x2,y2] that are centered (as far as possible)
                // around maxX,maxY
                int x1 = maxX - STAMP_SIZE, x2 = maxX + STAMP_SIZE;
                if(x1 < 0) { x1 = 0; x2 = 2*STAMP_SIZE; }
                else if(x2 >= width) { x2 = width-1; x1 = width - 2*STAMP_SIZE - 1; }
                int y1 = maxY - STAMP_SIZE, y2 = maxY + STAMP_SIZE;
                if(y1 < 0) { y1 = 0; y2 = 2*STAMP_SIZE; }
                else if(y2 >= height) { y2 = height-1; y1 = height - 2*STAMP_SIZE - 1; }

                // Fill in our Stamp structure
                _theStamp.elapsedMSecs = (uint32_t)(1e3*[timestamp timeIntervalSinceDate:_beginAt]);
                _theStamp.maxPixelIndex = maxIndex;
                _theStamp.exposureCount = self.exposureCount;
                uint8_t *rgbPtr = _theStamp.rgb;
                uint32_t *rawPtr = (uint32_t*)rawImageBytes + y1*width + x1;
                for(int y = 0; y < 2*STAMP_SIZE+1; ++y) {
                    for(int x = 0; x < 2*STAMP_SIZE+1; ++x) {
                        uint32_t raw = rawPtr[x]; // raw = AABBGGRR
                        *rgbPtr++ = (raw & 0xff); // Red
                        *rgbPtr++ = (raw & 0xff00) >> 8; // Green
                        *rgbPtr++ = (raw & 0xff0000) >> 16; // Blue
                    }
                    rawPtr += width;
                }
                
                // Save our Stamp structure to disk
                NSString *filename = [[NSString alloc] initWithFormat:@"stamp_%@.dat",[self.timestampFormatter stringFromDate:timestamp]];
                [self saveStampToFilename:filename];
                [self.cosmicStamps addObject:[NSValue valueWithBytes:_theStamp objCType:@encode(Stamp)]];
                
                
                NSValue *cosmicStamp = [self.cosmicStamps lastObject];
                Stamp buffer;
                [cosmicStamp getValue:buffer];
                
                
                self.saveCount++;
            }
            // Save fixed sub-image in first exposure, for debugging
            if(false && self.exposureCount == 0) {
                UIImage *img = [self createUIImageWithWidth:64 Height:64 AtLeftEdge:750 TopEdge:500 FromRawData:rawImageBytes WithRawWidth:width RawHeight:height];
                [self saveImageToFilesystem:img withIdentifier:@"testing"];
            }
            // Update our exposure statistics
            self.exposureCount++;
            if(self.exposureCount > 1 && self.exposureCount % 10 == 0) {
                NSTimeInterval elapsed = [timestamp timeIntervalSinceDate:_beginAt];
                NSLog(@"Exposure cycle time = %.3f sec, capture time = %.3f sec, saved %d / %d exposures",elapsed/self.exposureCount,_captureElapsed/self.exposureCount,self.saveCount,self.exposureCount);
            }
        }
        // All done with the image buffer so release it now
        CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
        
        // Update our delegate on the UI thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.brainDelegate setExposureCount:self.exposureCount];
            [self.brainDelegate stampAdded];
            [self captureImage];

        });
    }];
}

- (void) saveImageToFilesystem:(UIImage*)image withIdentifier:(NSString*)identifier {
    // Add this sub-image to our list of saved images
    NSURL *docsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *pathComponent = [NSString stringWithFormat:@"%@.png",identifier];
    NSURL *imageURL = [docsDirectory URLByAppendingPathComponent:pathComponent];
    NSError *writeError;
    [UIImagePNGRepresentation(image) writeToURL:imageURL options:NSDataWritingAtomic error:&writeError];
    //[UIImageJPEGRepresentation(image,1.0) writeToURL:imageURL options:NSDataWritingAtomic error:&writeError];
    if(VERBOSE) NSLog(@"Written To Filesystem at %@", imageURL);
    if(writeError) NSLog(@"Write to Filesystem Error: %@", writeError.userInfo);    
}

- (UIImage*) createUIImageWithWidth:(int)imageWidth Height:(int)imageHeight AtLeftEdge:(int)leftEdge TopEdge:(int)topEdge FromRawData:(unsigned char *)rawData WithRawWidth:(int)rawWidth RawHeight:(int)rawHeight {

    UIGraphicsBeginImageContext(CGSizeMake(imageWidth,imageHeight));
    CGContextRef c = UIGraphicsGetCurrentContext();

    // Initialize pointers to the top-left corner of the destination image and the source
    // rectangle in the raw data.
    unsigned int *imgPtr = (unsigned int*)CGBitmapContextGetData(c);
    unsigned int *rawPtr = (unsigned int*)rawData + topEdge*rawWidth + leftEdge;
    size_t bytesPerImgRow = 4*imageWidth;
    
    // Loop over rows to copy from the raw data into the image data array
    for(int y = 0; y < imageHeight; ++y) {
        memcpy(imgPtr,rawPtr,bytesPerImgRow);
        
        for(int x = 0; x < imageWidth; ++x) {
            unsigned int val = imgPtr[x];
            unsigned char R = (val & 0xff), G = (val & 0xff00) >> 8, B = (val & 0xff0000) >> 16, A = val>>24;
            unsigned int intensity = R+2*G+B;
            NSLog(@"dump (%d,%d) R=%d G=%d B=%d A=%d I=%d",x,y,R,G,B,A,intensity);
        }
        
        imgPtr += imageWidth;
        rawPtr += rawWidth;
    }
    
    //quick fix to sideways image problem
    UIImage *image = [[UIImage alloc] initWithCGImage:UIGraphicsGetImageFromCurrentImageContext().CGImage scale:1.0 orientation:UIImageOrientationRight];
 
    UIGraphicsEndImageContext();
    
    return image;
}

- (void) saveImageDataWithIdentifier:(NSString*)identifier Width:(int)imageWidth Height:(int)imageHeight AtLeftEdge:(int)leftEdge TopEdge:(int)topEdge FromRawData:(unsigned char *)rawData WithRawWidth:(int)rawWidth RawHeight:(int)rawHeight {
    
    if(VERBOSE) NSLog(@"Saving %@...",identifier);

    // Add this sub-image to our list of saved images
    NSURL *docsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSString *pathComponent = [NSString stringWithFormat:@"%@.dat",identifier];
    const char *filename = [[[docsDirectory URLByAppendingPathComponent:pathComponent] path] cStringUsingEncoding:NSASCIIStringEncoding];
    FILE *out = fopen(filename,"w");

    // Initialize pointer to the top-left corner of the source rectangle in the raw data.
    unsigned int *rawPtr = (unsigned int*)rawData + topEdge*rawWidth + leftEdge;
    
    // Loop over rows in the output image
    for(int y = 0; y < imageHeight; ++y) {
        for(int x = 0; x < imageWidth; ++x) {
            unsigned int val = rawPtr[x];
            unsigned char R = (val & 0xff), G = (val & 0xff00) >> 8, B = (val & 0xff0000) >> 16;
            fprintf(out,"  %4d %4d %4d",R,G,B);
        }
        fprintf(out,"\n");
        rawPtr += rawWidth;
    }
    fclose(out);
}

- (void) saveStampToFilename:(NSString*)filename {
/**
    NSLog(@"Saving stamp: elapsed = %u, index = %u, count = %u",_theStamp->elapsedMSecs,_theStamp->maxPixelIndex,_theStamp->exposureCount);
    uint8_t *ptr = _theStamp->rgb;
    for(int y = 0; y < 2*STAMP_SIZE+1; ++y) {
        for(int x = 0; x < 2*STAMP_SIZE+1; ++x) {
            uint8_t R= *ptr++, G = *ptr++, B = *ptr++;
            NSLog(@"[%2d,%2d] = (%3d,%3d,%3d) %4d",x,y,R,G,B,R+2*G+B);
        }
    }
**/
    // Generate the filename for this stamp
    NSURL *docsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    const char *fullName = [[[docsDirectory URLByAppendingPathComponent:filename] path] cStringUsingEncoding:NSASCIIStringEncoding];

    // Save the stamp in binary format
    FILE *out = fopen(fullName,"wb");
    fwrite(_theStamp, sizeof(Stamp), 1, out);
    fclose(out);
}

@end
