#import "ImagePipelineManager.h"
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
    assert(rawImage.width);
    assert(rawImage.height);
    
    if (!_rawTxt || [_rawTxt width]!=rawImage.width || [_rawTxt height]!=rawImage.height) {
        _rawTxt = Pipeline::TextureForRaw(renderer, rawImage.width, rawImage.height, rawImage.pixels);
    }
    
    if (!result.txt) {
        result.txt = renderer.textureCreate(_rawTxt, MTLPixelFormatRGBA32Float);
    }
    
    result.debayer = Pipeline::Debayer(renderer, debayerOptions, _rawTxt, result.txt);
    
    ccm = {
        .illum = (estimateIlluminant ? debayerResult.illum : ColorRaw(opts.whiteBalance.illum)),
        .matrix = (estimateIlluminant ? ColorMatrixForIlluminant(debayerResult.illum).matrix : ColorMatrix((double*)opts.whiteBalance.colorMatrix))
    };
    
    Pipeline::Process(renderer, processOptions, result.txt, result.txt);
    renderer.sync(result.txt);
    renderer.commitAndWait();
    if (renderCallback) renderCallback();
}

@end
