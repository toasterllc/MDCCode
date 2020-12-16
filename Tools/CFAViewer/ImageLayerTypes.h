#import "MetalTypes.h"

namespace ImageLayerTypes {
    struct RenderContext {
        MetalTypes::ColorMatrix colorMatrix = {
            {1, 0, 0},
            {0, 1, 0},
            {0, 0, 1},
        };
        
        uint32_t viewWidth = 0;
        uint32_t viewHeight = 0;
        
        uint32_t imageWidth = 0;
        uint32_t imageHeight = 0;
        
        // Returns the number of image pixels that will be rendered
        uint32_t pixelCount() const {
            return imageWidth*imageHeight;
        }
    };
};
