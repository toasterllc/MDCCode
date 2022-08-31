#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import "ImagePipeline.h"
#import "Tools/Shared/Renderer.h"

@interface ImagePipelineManager : NSObject {
@public
    MDCTools::Renderer renderer;
    MDCTools::ImagePipeline::Pipeline::RawImage rawImage;
    MDCTools::ImagePipeline::Pipeline::Options options;
    MDCTools::ImagePipeline::Pipeline::Result result;
    std::function<void()> renderCallback;
}
- (void)render;
@end
