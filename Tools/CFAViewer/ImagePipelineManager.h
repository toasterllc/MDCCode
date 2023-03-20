#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <optional>
#import "ImagePipeline.h"
#import "Tools/Shared/Renderer.h"

@interface ImagePipelineManager : NSObject {
@public
    MDCTools::Renderer renderer;
    
    struct {
        size_t width;
        size_t height;
        Img::Pixel pixels[2200*2200];
    } rawImage;
    
    MDCTools::ImagePipeline::Pipeline::DebayerOptions debayerOptions;
    MDCTools::ImagePipeline::Pipeline::ProcessOptions processOptions;
    
    struct {
        MDCTools::ImagePipeline::Pipeline::DebayerResult debayer;
        MDCTools::Renderer::Txt txt;
    } result;
    
    std::function<void()> renderCallback;
}
- (void)render;
@end
