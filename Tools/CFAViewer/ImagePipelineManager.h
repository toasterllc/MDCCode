#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import "ImagePipeline.h"
#import "Tools/Shared/Renderer.h"

@interface ImagePipelineManager : NSObject {
@public
    MDCTools::Renderer renderer;
    MDCStudio::ImagePipeline::Pipeline::RawImage rawImage;
    MDCStudio::ImagePipeline::Pipeline::Options options;
    MDCStudio::ImagePipeline::Pipeline::Result result;
    std::function<void()> renderCallback;
}
- (void)render;
@end
