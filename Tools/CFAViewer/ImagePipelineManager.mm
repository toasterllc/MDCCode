#import "ImagePipelineManager.h"
#import "EstimateIlluminant.h"
using namespace MDCTools;
using namespace MDCTools::ImagePipeline;

@implementation ImagePipelineManager {
    Renderer::Txt _rawTxt;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) throw std::runtime_error("MTLCreateSystemDefaultDevice returned nil");
    renderer = MDCTools::Renderer(device, [device newDefaultLibrary], [device newCommandQueue]);
    
    return self;
}

 - (void)render {
    assert(rawImage);
    assert(rawImage->width);
    assert(rawImage->height);
    
    if (!_rawTxt || [_rawTxt width]!=rawImage->width || [_rawTxt height]!=rawImage->height) {
        _rawTxt = Pipeline::TextureForRaw(renderer, rawImage->width, rawImage->height, rawImage->pixels);
    }
    
    if (!result.txt) {
        result.txt = renderer.textureCreate(_rawTxt, MTLPixelFormatRGBA32Float);
    }
    
    ColorRaw i;
    if (illum) {
        i = *illum;
    } else {
        EstimateIlluminant::Run(renderer, <#const MDCTools::CFADesc &cfaDesc#>, <#id<MTLTexture> raw#>)
    }
    
    // Debayer
    auto dopts = debayerOptions;
    result.debayer = Pipeline::Debayer(renderer, dopts, _rawTxt, result.txt);
    
    // Process
    auto popts = processOptions;
    if (!popts.illum) popts.illum = result.debayer.illum;
    Pipeline::Process(renderer, popts, result.txt, result.txt);
    
    renderer.sync(result.txt);
    renderer.commitAndWait();
    if (renderCallback) renderCallback();
}

@end
