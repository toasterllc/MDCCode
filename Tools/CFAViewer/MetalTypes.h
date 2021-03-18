#import <simd/simd.h>

#ifdef __METAL_VERSION__
#define MetalShaderContext 1
#else
#define MetalShaderContext 0
#endif

#if MetalShaderContext
#define MetalConst constant
#define MetalDevice device
#else
#import <atomic>
#define MetalConst const
#define MetalDevice
#endif

namespace CFAViewer {
    namespace MetalTypes {
        using ImagePixel = uint16_t;
        MetalConst ImagePixel ImagePixelMax = 0x0FFF; // 12 bit values
        
        struct Histogram {
            static MetalConst size_t Count = 1<<12;
            uint32_t r[Count];
            uint32_t g[Count];
            uint32_t b[Count];
            
            Histogram() : r{}, g{}, b{} {}
        };
        
        struct HistogramFloat {
            float r[Histogram::Count];
            float g[Histogram::Count];
            float b[Histogram::Count];
            
            HistogramFloat() : r{}, g{}, b{} {}
        };
        
        struct Vals3 {
            uint32_t x = 0;
            uint32_t y = 0;
            uint32_t z = 0;
        };
        
        // Unique vertexes (defines a unit square)
        MetalConst vector_float4 SquareVert[4] = {
            { 1,  1, 0, 1},
            {-1,  1, 0, 1},
            {-1, -1, 0, 1},
            { 1, -1, 0, 1},
        };
        
        // Vertex indicies (for a square)
        MetalConst uint8_t SquareVertIdx[6] = {
            0, 1, 2,
            0, 2, 3,
        };
        
        MetalConst size_t SquareVertIdxCount = sizeof(SquareVertIdx)/sizeof(*SquareVertIdx);
    };
};
