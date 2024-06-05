#import "Code/Lib/Toastbox/Mac/MetalUtil.h"

#if !MetalShaderContext
#import <Metal/Metal.h>
#endif // !MetalShaderContext

namespace ImagePipeline {

#define ImagePipelineShaderNamespace "ImagePipeline::Shader::"

using ImagePixel = uint16_t;
constexpr MetalConstant ImagePixel ImagePixelMax = 0x0FFF; // 12 bit values

struct Vals3 {
    uint32_t x = 0;
    uint32_t y = 0;
    uint32_t z = 0;
};

struct SampleRect {
    int32_t left = 0;
    int32_t right = 0;
    int32_t top = 0;
    int32_t bottom = 0;
    
    int32_t width() const MetalConstant { return right-left; }
    int32_t height() const MetalConstant { return bottom-top; }
    int32_t count() const MetalConstant { return width()*height(); }
    bool empty() const MetalConstant { return !width() || !height(); }
    
    bool contains(int32_t x, int32_t y) const MetalConstant {
        return
            x >= (int32_t)left   &&
            x < (int32_t)right   &&
            y >= (int32_t)top    &&
            y < (int32_t)bottom  ;
    }
    
    template <typename T>
    bool contains(T pos) const MetalConstant {
        return contains(pos.x, pos.y);
    }
};

struct TimestampContext {
    simd::float2 timestampOffset; // [0,1] Cartesion
    simd::float2 timestampSize;   // [0,1]
};

} // namespace ImagePipeline
