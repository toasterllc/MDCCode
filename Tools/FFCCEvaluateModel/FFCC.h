#import "Mat.h"

namespace FFCC {
    using Mat64 = Mat<double,64,64>;
    using Mat64c = Mat<std::complex<double>,64,64>;
    
    struct Model {
        struct Params {
            struct {
                double vonMisesDiagonalEps = 0;
            } hyperparams;
            
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
}
