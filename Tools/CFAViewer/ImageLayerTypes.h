#import "MetalTypes.h"

namespace CFAViewer {
    namespace ImageLayerTypes {
        struct RenderContext {
            simd::float3x3 colorMatrix = {
                simd::float3{1,0,0},
                simd::float3{0,1,0},
                simd::float3{0,0,1},
            };
            
            struct {
                uint32_t left = 0;
                uint32_t right = 0;
                uint32_t top = 0;
                uint32_t bottom = 0;
                
                uint32_t width() MetalConst { return right-left; }
                uint32_t height() MetalConst { return bottom-top; }
                uint32_t count() MetalConst { return width()*height(); }
            } sampleRect;
            
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
};
