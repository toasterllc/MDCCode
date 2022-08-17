#import "ImagePipelineManager.h"
using namespace MDCStudio::ImagePipeline;

@implementation ImagePipelineManager

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) throw std::runtime_error("MTLCreateSystemDefaultDevice returned nil");
    renderer = MDCTools::Renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
    
    return self;
}

- (void)render {
    // Clear `result` so that the Renderer::Txt and Renderer::Buf objects that
    // it contains are destroyed before we render again, so they can be reused
    // for this render run.
    result = {};
    result = MDCStudio::ImagePipeline::Pipeline::Run(renderer, rawImage, options);
    if (renderCallback) renderCallback();
}

@end
