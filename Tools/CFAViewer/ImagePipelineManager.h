#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <optional>
#import "ImagePipeline.h"
#import "Code/Lib/Toastbox/Mac/Renderer.h"
#import "Img.h"
#import "RawImage.h"

@interface ImagePipelineManager : NSObject {
@public
    MDCTools::Renderer renderer;
    
    std::optional<RawImage> rawImage;
    std::optional<MDCTools::ImagePipeline::ColorRaw> illum;
    MDCTools::ImagePipeline::Pipeline::DebayerOptions debayerOptions;
    MDCTools::ImagePipeline::Pipeline::ProcessOptions processOptions;
    
    struct {
        MDCTools::ImagePipeline::ColorRaw illum;
        MDCTools::ImagePipeline::ColorMatrix colorMatrix;
        MDCTools::Renderer::Txt txt;
    } result;
    
    std::function<void()> renderCallback;
}
- (void)render;
@end
