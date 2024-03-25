#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "../Color.h"
#import "FFCC.h"
#import "Code/Lib/Toastbox/Mac/Renderer.h"

namespace MDCTools::ImagePipeline {

class EstimateIlluminant {
public:
    static MDCTools::Color<MDCTools::ColorSpace::Raw> Run(
        Toastbox::Renderer& renderer,
        const MDCTools::CFADesc& cfaDesc,
        id<MTLTexture> raw
    ) {
        return FFCC::Run(_Model, renderer, cfaDesc, raw);
    }
    
private:
    static const FFCC::Model _Model;
    static const uint64_t _F_fft0Vals[8192];
    static const uint64_t _F_fft1Vals[8192];
    static const uint64_t _BVals[4096];
};

} // namespace MDCTools::ImagePipeline
