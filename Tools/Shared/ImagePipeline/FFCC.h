#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "Code/Lib/Toastbox/Mac/Mat.h"
#import "Code/Lib/Toastbox/Mac/CFA.h"
#import "Code/Lib/Toastbox/Mac/Renderer.h"

class FFCC {
public:
    using Mat64 = Toastbox::Mat<double,64,64>;
    using Mat64c = Toastbox::Mat<std::complex<double>,64,64>;
    using Vec2 = Toastbox::Mat<double,2,1>;
    using Vec3 = Toastbox::Mat<double,3,1>;
    
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
    
    static Vec3 Run(
        const Model& model,
        Toastbox::Renderer& renderer,
        const Toastbox::CFADesc& cfaDesc,
        id<MTLTexture> raw
    );
};
