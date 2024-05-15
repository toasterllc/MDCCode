#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "ImagePipelineTypes.h"
#import "Code/Lib/Toastbox/Mac/Mat.h"
#import "Code/Lib/Toastbox/Mac/CFA.h"
#import "Code/Lib/Toastbox/Mac/Renderer.h"

namespace MDCTools::ImagePipeline {

class Defringe {
public:
    struct Options {
        uint32_t rounds = 2;
        float αthresh = 2; // Threshold to allow α correction
        float γthresh = .2; // Threshold to allow γ correction
        float γfactor = .5; // Weight to apply to r̄ vs r when doing γ correction
        float δfactor = 10./16; // Weight to apply to center vs adjacent pixels when
                                // computing derivative, when solving for tile shift
    };
    
    static void Run(
        Toastbox::Renderer& renderer,
        const Toastbox::CFADesc& cfaDesc,
        const Options& opts, id<MTLTexture> raw
    );
};

}; // MDCTools::ImagePipeline
