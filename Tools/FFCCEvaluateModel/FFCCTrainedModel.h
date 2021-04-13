#import "FFCC.h"

namespace FFCCTrainedModel {
    #include "FFCCTrainedModelVals.h"
    
    const FFCC::Model Model = {
        .params = {
            .hyperparams = {
                .vonMisesDiagonalEps = 0.074325444687670, // params.HYPERPARAMS.VON_MISES_DIAGONAL_EPS
            },
            
            .histogram = {
                .binCount = 64,             // params.HISTOGRAM.NUM_BINS
                .binSize = 1./32,           // params.HISTOGRAM.BIN_SIZE
                .startingUV = -0.531250,    // params.HISTOGRAM.STARTING_UV
                .minIntensity = 1./256,     // params.HISTOGRAM.MINIMUM_INTENSITY
            },
        },
        
        .F_fft = {
            (std::complex<double>*)F_fft0Vals,
            (std::complex<double>*)F_fft1Vals,
        },
        .B = (double*)BVals,
    };
};
