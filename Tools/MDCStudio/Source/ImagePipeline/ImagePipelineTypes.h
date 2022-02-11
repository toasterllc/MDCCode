#import "Tools/Shared/MetalUtil.h"

#if !MetalShaderContext
#import <Metal/Metal.h>
#endif // !MetalShaderContext

namespace MDCStudio {
namespace ImagePipeline {

#define ImagePipelineShaderNamespace "MDCStudio::ImagePipeline::Shader::"

using ImagePixel = uint16_t;
MetalConst ImagePixel ImagePixelMax = 0x0FFF; // 12 bit values

struct Vals3 {
    uint32_t x = 0;
    uint32_t y = 0;
    uint32_t z = 0;
};

enum class CFAColor : uint8_t {
    Red     = 0,
    Green   = 1,
    Blue    = 2,
};

struct CFADesc {
    CFADesc() {}
    CFADesc(CFAColor tl, CFAColor tr, CFAColor bl, CFAColor br) :
    desc{{tl,tr},{bl,br}} {}
    
    CFAColor desc[2][2] = {};
    
    template <typename T>
    CFAColor color(T x, T y) MetalConst {
        return desc[y&1][x&1];
    }
    
    template <typename T>
    CFAColor color(T pos) MetalConst {
        return color(pos.x, pos.y);
    }
};

struct SampleRect {
    int32_t left = 0;
    int32_t right = 0;
    int32_t top = 0;
    int32_t bottom = 0;
    
    int32_t width() MetalConst { return right-left; }
    int32_t height() MetalConst { return bottom-top; }
    int32_t count() MetalConst { return width()*height(); }
    bool empty() MetalConst { return !width() || !height(); }
    
    bool contains(int32_t x, int32_t y) MetalConst {
        return
            x >= (int32_t)left   &&
            x < (int32_t)right   &&
            y >= (int32_t)top    &&
            y < (int32_t)bottom  ;
    }
    
    template <typename T>
    bool contains(T pos) MetalConst {
        return contains(pos.x, pos.y);
    }
};

} // namespace ImagePipeline
} // namespace MDCStudio
