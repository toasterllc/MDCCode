#import <simd/simd.h>

namespace MDCImageLayerTypes {
    using ImagePixel = uint16_t;
    
#if !__METAL_VERSION__
    const ImagePixel ImagePixelMax = 0x0FFF; // 12 bit values
#else
    constant ImagePixel ImagePixelMax = 0x0FFF; // 12 bit values
#endif
    
    struct RenderContext {
        // Unique vertices (defines a unit square)
        const vector_float4 v[4] = {
            { 1,  1, 0, 1},
            {-1,  1, 0, 1},
            {-1, -1, 0, 1},
            { 1, -1, 0, 1},
        };
        
        // Vertex indicies (for a square)
        const uint8_t vi[6] = {
            0, 1, 2,
            0, 2, 3,
        };
        
        uint32_t viewWidth = 0;
        uint32_t viewHeight = 0;
        
        uint32_t imageWidth = 0;
        uint32_t imageHeight = 0;
        
        // Returns the number of image pixels that will be rendered
        uint32_t pixelCount() const {
            return imageWidth*imageHeight;
        }
        
        // Returns the number of vertices
        uint32_t vertexCount() const {
            return sizeof(vi)/sizeof(*vi);
        }
    };
};
