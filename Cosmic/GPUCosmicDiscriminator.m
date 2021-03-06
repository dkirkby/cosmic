#import "GPUCosmicDiscriminator.h"

// See http://stackoverflow.com/questions/12168072/fragment-shader-average-luminosity/12169560#12169560
// for details on how the GPUImageAverageColor filter that this is based on works. For a similar max finder, see
// http://stackoverflow.com/questions/12488049/glsl-how-to-access-pixel-data-of-a-texture-is-glsl-shader

NSString *const kGPUCosmicDiscriminatorVertexShaderString = SHADER_STRING
(
 attribute vec4 position;
 attribute vec4 inputTextureCoordinate;
 
 uniform float texelWidth;
 uniform float texelHeight;
 
 varying vec2 upperLeftInputTextureCoordinate;
 varying vec2 upperRightInputTextureCoordinate;
 varying vec2 lowerLeftInputTextureCoordinate;
 varying vec2 lowerRightInputTextureCoordinate;
 
 void main()
 {
     gl_Position = position;
     
     upperLeftInputTextureCoordinate = inputTextureCoordinate.xy + vec2(-texelWidth, -texelHeight);
     upperRightInputTextureCoordinate = inputTextureCoordinate.xy + vec2(texelWidth, -texelHeight);
     lowerLeftInputTextureCoordinate = inputTextureCoordinate.xy + vec2(-texelWidth, texelHeight);
     lowerRightInputTextureCoordinate = inputTextureCoordinate.xy + vec2(texelWidth, texelHeight);
 }
 );

NSString *const kGPUCosmicDiscriminatorFragmentShaderString = SHADER_STRING
(
 precision highp float;
 
 const highp vec3 W = vec3(0.25, 0.50, 0.25);
 
 uniform sampler2D inputImageTexture;
 
 varying highp vec2 outputTextureCoordinate;
 
 varying highp vec2 upperLeftInputTextureCoordinate;
 varying highp vec2 upperRightInputTextureCoordinate;
 varying highp vec2 lowerLeftInputTextureCoordinate;
 varying highp vec2 lowerRightInputTextureCoordinate;
 
 void main()
 {
     highp vec4 upperLeftColor = texture2D(inputImageTexture, upperLeftInputTextureCoordinate);
     highp vec4 upperRightColor = texture2D(inputImageTexture, upperRightInputTextureCoordinate);
     highp vec4 lowerLeftColor = texture2D(inputImageTexture, lowerLeftInputTextureCoordinate);
     highp vec4 lowerRightColor = texture2D(inputImageTexture, lowerRightInputTextureCoordinate);

     highp float upperLeftIntensity = dot(upperLeftColor.rgb, W);
     highp float upperRightIntensity = dot(upperRightColor.rgb, W);
     highp float lowerLeftIntensity = dot(lowerLeftColor.rgb, W);
     highp float lowerRightIntensity = dot(lowerRightColor.rgb, W);

     highp vec4 outputColor;
     outputColor = vec4(upperLeftInputTextureCoordinate,lowerRightInputTextureCoordinate);
     //outputColor.r = 0.5;
     //outputColor.g = 0.25;
     //outputColor.b = 0.75;
     //outputColor.a = 1.0;
     
     gl_FragColor = outputColor;
 }
);

@interface GPUCosmicDiscriminator () {
    BOOL _firstTime;
}

@end

@implementation GPUCosmicDiscriminator

@synthesize cosmicDiscriminatorFinishedBlock = _cosmicDiscriminatorFinishedBlock;

#pragma mark -
#pragma mark Initialization and teardown

- (id)init;
{
    if (!(self = [super initWithVertexShaderFromString:kGPUCosmicDiscriminatorVertexShaderString fragmentShaderFromString:kGPUCosmicDiscriminatorFragmentShaderString]))
    {
        return nil;
    }
    
    texelWidthUniform = [filterProgram uniformIndex:@"texelWidth"];
    texelHeightUniform = [filterProgram uniformIndex:@"texelHeight"];
    
    stageTextures = [[NSMutableArray alloc] init];
    stageFramebuffers = [[NSMutableArray alloc] init];
    stageSizes = [[NSMutableArray alloc] init];
    
    __unsafe_unretained GPUCosmicDiscriminator *weakSelf = self;
    [self setFrameProcessingCompletionBlock:^(GPUImageOutput *filter, CMTime frameTime) {
        [weakSelf finalizeAtFrameTime:frameTime];
    }];

    _firstTime = YES;
    
    return self;
}

- (void)dealloc;
{
    if (rawImagePixels != NULL)
    {
        free(rawImagePixels);
    }
}

#pragma mark -
#pragma mark Manage the output texture

- (void)initializeOutputTextureIfNeeded;
{
    if (inputTextureSize.width < 1.0)
    {
        return;
    }
    
    // Create textures for each level
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];

        NSUInteger nReductions = 4;
        int width = (int)floor(inputTextureSize.width+0.5);
        int height = (int)floor(inputTextureSize.height+0.5);
        NSAssert(width % (1<<nReductions) == 0,
                 @"Input texture width %d is not a multiple of %d.",width,(1<<nReductions));
        NSAssert(height % (1<<nReductions) == 0,
                 @"Input texture height %d is not a multiple of %d.",height,(1<<nReductions));
        NSLog(@"Will reduce %u times for size %f x %f", nReductions,inputTextureSize.width,inputTextureSize.height);
        NSUInteger divisor = 1;
        for (NSUInteger currentReduction = 0; currentReduction < nReductions; currentReduction++) {
            divisor *= 2;
            CGSize currentStageSize = CGSizeMake(width/divisor, height/divisor);
            
            [stageSizes addObject:[NSValue valueWithCGSize:currentStageSize]];

            GLuint textureForStage;
            glGenTextures(1, &textureForStage);
            glBindTexture(GL_TEXTURE_2D, textureForStage);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            [stageTextures addObject:[NSNumber numberWithInt:textureForStage]];
            
            NSLog(@"At reduction: %d size in X: %f, size in Y:%f", currentReduction, currentStageSize.width, currentStageSize.height);
        }
    });
}

- (void)deleteOutputTexture;
{
    if ([stageTextures count] == 0)
    {
        return;
    }
    
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        
        NSUInteger numberOfStageTextures = [stageTextures count];
        for (NSUInteger currentStage = 0; currentStage < numberOfStageTextures; currentStage++)
        {
            GLuint currentTexture = [[stageTextures objectAtIndex:currentStage] intValue];
            glDeleteTextures(1, &currentTexture);
        }
        
        [stageTextures removeAllObjects];
        [stageSizes removeAllObjects];
    });
}

#pragma mark -
#pragma mark Managing the display FBOs

- (void)recreateFilterFBO
{
    cachedMaximumOutputSize = CGSizeZero;
    [self destroyFilterFBO];    
    [self deleteOutputTexture];
    [self initializeOutputTextureIfNeeded];
    
    [self setFilterFBO];
}

- (void)createFilterFBOofSize:(CGSize)currentFBOSize;
{
    // Create framebuffers for each level
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        glActiveTexture(GL_TEXTURE1);
        
        NSUInteger numberOfStageFramebuffers = [stageTextures count];
        for (NSUInteger currentStage = 0; currentStage < numberOfStageFramebuffers; currentStage++)
        {
            GLuint currentFramebuffer;
            glGenFramebuffers(1, &currentFramebuffer);
            glBindFramebuffer(GL_FRAMEBUFFER, currentFramebuffer);
            [stageFramebuffers addObject:[NSNumber numberWithInt:currentFramebuffer]];
            
            GLuint currentTexture = [[stageTextures objectAtIndex:currentStage] intValue];
            glBindTexture(GL_TEXTURE_2D, currentTexture);
            
            CGSize currentFramebufferSize = [[stageSizes objectAtIndex:currentStage] CGSizeValue];
            
            NSLog(@"FBO stage size: %f, %f", currentFramebufferSize.width, currentFramebufferSize.height);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)currentFramebufferSize.width, (int)currentFramebufferSize.height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, currentTexture, 0);
            GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
            
            NSAssert(status == GL_FRAMEBUFFER_COMPLETE, @"Incomplete filter FBO: %d", status);
        }
    });
    
//    [self notifyTargetsAboutNewOutputTexture];
}

- (void)destroyFilterFBO;
{
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        
        NSUInteger numberOfStageFramebuffers = [stageFramebuffers count];
        for (NSUInteger currentStage = 0; currentStage < numberOfStageFramebuffers; currentStage++)
        {
            GLuint currentFramebuffer = [[stageFramebuffers objectAtIndex:currentStage] intValue];
            glDeleteFramebuffers(1, &currentFramebuffer);
        }
        
        [stageFramebuffers removeAllObjects];
    });
}

- (void)renderToTextureWithVertices:(const GLfloat *)vertices textureCoordinates:(const GLfloat *)textureCoordinates sourceTexture:(GLuint)sourceTexture;
{
    if (self.preventRendering)
    {
        return;
    }
    
    [GPUImageContext setActiveShaderProgram:filterProgram];

    glVertexAttribPointer(filterPositionAttribute, 2, GL_FLOAT, 0, 0, vertices);
    glVertexAttribPointer(filterTextureCoordinateAttribute, 2, GL_FLOAT, 0, 0, textureCoordinates);

    GLuint currentTexture = sourceTexture;
    
    NSUInteger numberOfStageFramebuffers = [stageFramebuffers count];
    for (NSUInteger currentStage = 0; currentStage < numberOfStageFramebuffers; currentStage++)
    {
        GLuint currentFramebuffer = [[stageFramebuffers objectAtIndex:currentStage] intValue];
        glBindFramebuffer(GL_FRAMEBUFFER, currentFramebuffer);
        
        CGSize currentStageSize = [[stageSizes objectAtIndex:currentStage] CGSizeValue];
        glViewport(0, 0, (int)currentStageSize.width, (int)currentStageSize.height);

        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D, currentTexture);
        
        glUniform1i(filterInputTextureUniform, 2);
        
        glUniform1f(texelWidthUniform, 0.5 / currentStageSize.width);
        glUniform1f(texelHeightUniform, 0.5 / currentStageSize.height);
        
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

        currentTexture = [[stageTextures objectAtIndex:currentStage] intValue];

        if(_firstTime) {
            NSUInteger width = (int)currentStageSize.width;
            NSUInteger height = (int)currentStageSize.height;
            NSUInteger totalBytesForImage = 4*width*height;
            GLubyte *rawImagePixels2 = (GLubyte *)malloc(totalBytesForImage);
            glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, rawImagePixels2);

            NSUInteger totalNumberOfPixels = totalBytesForImage / 4;
            for (NSUInteger currentPixel = 0; currentPixel < totalNumberOfPixels; currentPixel++) {
                NSUInteger row = currentPixel / width;
                NSUInteger col = currentPixel % width;
                if(row < 4 && col < 4) {
                    GLubyte r = rawImagePixels2[currentPixel*4];
                    GLubyte g = rawImagePixels2[currentPixel*4+1];
                    GLubyte b = rawImagePixels2[currentPixel*4+2];
                    GLubyte a = rawImagePixels2[currentPixel*4+3];
                    NSLog(@"RGBA[%d,%d,%d] = %02x %02x %02x %02x",currentStage,row,col,r,g,b,a);
                }
            }
        }
    }
    _firstTime = NO;
}

- (void)prepareForImageCapture;
{
    preparedToCaptureImage = YES;
}

- (void)setInputRotation:(GPUImageRotationMode)newInputRotation atIndex:(NSInteger)textureIndex;
{
    inputRotation = kGPUImageNoRotation;
}

- (void)finalizeAtFrameTime:(CMTime)frameTime;
{
    CGSize finalStageSize = [[stageSizes lastObject] CGSizeValue];
    NSUInteger totalNumberOfPixels = round(finalStageSize.width * finalStageSize.height);
    
    if (rawImagePixels == NULL)
    {
        rawImagePixels = (GLubyte *)malloc(totalNumberOfPixels * 4);
    }

    glReadPixels(0, 0, (int)finalStageSize.width, (int)finalStageSize.height, GL_RGBA, GL_UNSIGNED_BYTE, rawImagePixels);
    
    NSUInteger redTotal = 0, greenTotal = 0, blueTotal = 0, alphaTotal = 0;
    NSUInteger byteIndex = 0;
    for (NSUInteger currentPixel = 0; currentPixel < totalNumberOfPixels; currentPixel++)
    {
        redTotal += rawImagePixels[byteIndex++];
        greenTotal += rawImagePixels[byteIndex++];
        blueTotal += rawImagePixels[byteIndex++];
        alphaTotal += rawImagePixels[byteIndex++];
    }
/*
    CGFloat normalizedRedTotal = (CGFloat)redTotal / (CGFloat)totalNumberOfPixels / 255.0;
    CGFloat normalizedGreenTotal = (CGFloat)greenTotal / (CGFloat)totalNumberOfPixels / 255.0;
    CGFloat normalizedBlueTotal = (CGFloat)blueTotal / (CGFloat)totalNumberOfPixels / 255.0;
    CGFloat normalizedAlphaTotal = (CGFloat)alphaTotal / (CGFloat)totalNumberOfPixels / 255.0;
*/    
    if (_cosmicDiscriminatorFinishedBlock != NULL)
    {
        _cosmicDiscriminatorFinishedBlock(frameTime);
    }
}

@end
