#import "MetalTypes.h"
#import "Enum.h"

namespace CFAViewer {
    namespace ImageLayerTypes {
        Enum(uint8_t, PxColor, PxColors,
            Red     = 0,
            Green   = 1,
            Blue    = 2,
        );
        
        struct RenderContext {
            simd::float3x3 colorMatrix = {
                simd::float3{1,0,0},
                simd::float3{0,1,0},
                simd::float3{0,0,1},
            };
            
            simd::float3 whitePoint_XYY_D50;
            simd::float3 whitePoint_CamRaw_D50;
            
            simd::float3 highlightFactorR = {0,0,0};
            simd::float3 highlightFactorG = {0,0,0};
            simd::float3 highlightFactorB = {0,0,0};
            
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
            
            PxColor cfa[2][2] = {{
                PxColors::Green,
                PxColors::Red,
            }, {
                PxColors::Blue,
                PxColors::Green,
            }};
            
            PxColor cfaColor(size_t x, size_t y) MetalConst {
                return cfa[y&1][x&1];
            }
        };
    };
};
