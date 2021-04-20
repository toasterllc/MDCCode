#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "Color.h"
#import "Renderer.h"
#import "FFCC.h"

namespace CFAViewer::ImagePipeline {

class EstimateIlluminantFFCC {
public:
    static Color<ColorSpace::Raw> Run(Renderer& renderer, const CFADesc& cfaDesc, id<MTLTexture> raw) {
        return FFCC::EstimateIlluminant(_Model, renderer, cfaDesc, raw);
    }
    
private:
    static const uint64_t _F_fft0Vals[8192];
    static const uint64_t _F_fft1Vals[8192];
    static const uint64_t _BVals[4096];
    static const FFCC::Model _Model;
};

}; // namespace CFAViewer::ImagePipeline
