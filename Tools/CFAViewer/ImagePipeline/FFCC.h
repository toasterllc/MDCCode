#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "ImagePipelineTypes.h"
#import "MetalUtil.h"
#import "Color.h"
#import "Renderer.h"
#import "Mod.h"

class FFCC {
public:
    using Mat64 = Mat<double,64,64>;
    using Mat64c = Mat<std::complex<double>,64,64>;
    using Vec2 = Mat<double,2,1>;
    using Vec3 = Mat<double,3,1>;
    
    struct Model {
        struct Params {
            struct {
                size_t binCount = 0;
                double binSize = 0;
                double startingUV = 0;
                double minIntensity = 0;
            } histogram;
        };
        
        Params params;
        Mat64c F_fft[2];
        Mat64 B;
    };
    
    static Vec3 EstimateIlluminant(
        const Model& model,
        CFAViewer::Renderer& renderer,
        const CFAViewer::ImagePipeline::CFADesc& cfaDesc,
        id<MTLTexture> raw
    );
};

