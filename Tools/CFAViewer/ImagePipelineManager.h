#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <optional>
#import "ImagePipeline.h"
#import "Tools/Shared/Renderer.h"
#import "Img.h"
#import "RawImage.h"

@interface ImagePipelineManager : NSObject {
@public
    MDCTools::Renderer renderer;
    std::optional<RawImage> rawImage;
    
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
