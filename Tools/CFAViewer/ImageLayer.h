#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
@class ImagePipelineManager;

@interface ImageLayer : CAMetalLayer
- (void)setImagePipelineManager:(ImagePipelineManager*)ipm;
@end
