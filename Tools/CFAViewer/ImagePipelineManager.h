#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import "ImagePipeline.h"
#import "Renderer.h"

@interface ImagePipelineManager : NSObject {
@public
    CFAViewer::Renderer renderer;
    CFAViewer::ImagePipeline::Pipeline::RawImage rawImage;
    CFAViewer::ImagePipeline::Pipeline::Options options;
    CFAViewer::ImagePipeline::Pipeline::Result result;
    std::function<void()> renderCallback;
}
- (void)render;
@end
