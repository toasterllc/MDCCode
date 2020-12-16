#import "MetalTypes.h"

namespace HistogramLayerTypes {
    struct RenderContext {
        uint32_t viewWidth = 0;
        uint32_t viewHeight = 0;
        vector_float3 maxVals;
    };
};
