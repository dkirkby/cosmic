#import "GPUThresholdFilter.h"

NSString *const kGPUThresholdFragmentShaderString = SHADER_STRING
( 
 varying highp vec2 textureCoordinate;
 
 uniform sampler2D inputImageTexture;
 uniform highp float threshold;
 
 const highp vec3 W = vec3(0.25, 0.50, 0.25);

 void main()
 {
     highp vec4 textureColor = texture2D(inputImageTexture, textureCoordinate);
     highp float intensity = dot(textureColor.rgb, W);
     highp float thresholdResult = step(threshold, intensity);

     highp vec4 outputColor;
     outputColor.r = thresholdResult*textureColor.r;
     outputColor.g = thresholdResult*textureColor.g;
     outputColor.b = thresholdResult*textureColor.b;
     outputColor.a = 1.0;

     gl_FragColor = outputColor;
 }
);

@implementation GPUThresholdFilter

@synthesize threshold = _threshold;

#pragma mark -
#pragma mark Initialization

- (id)init;
{
    if (!(self = [super initWithFragmentShaderFromString:kGPUThresholdFragmentShaderString]))
    {
		return nil;
    }
    
    thresholdUniform = [filterProgram uniformIndex:@"threshold"];
    self.threshold = 0.5;
    
    return self;
}

#pragma mark -
#pragma mark Accessors

- (void)setThreshold:(CGFloat)newValue;
{
    _threshold = newValue;
    
    [self setFloat:_threshold forUniform:thresholdUniform program:filterProgram];
}

@end

