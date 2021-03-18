#import <simd/simd.h>

#ifdef __METAL_VERSION__
#define MetalShaderContext 1
#else
#define MetalShaderContext 0
#endif

#if !MetalShaderContext
#import <atomic>
#endif

#if MetalShaderContext
#define MetalConst constant
#define MetalDevice device
#else
#define MetalConst const
#define MetalDevice
#endif

namespace CFAViewer {
namespace MetalUtil {

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

#if MetalShaderContext

namespace Standard {
    using namespace metal;
    
    struct VertexOutput {
        float4 pos [[position]];
        float2 posUnit;
    };
    
    inline VertexOutput VertexShader(uint vidx) {
        VertexOutput r = {
            .pos = SquareVert[SquareVertIdx[vidx]],
            .posUnit = SquareVert[SquareVertIdx[vidx]].xy,
        };
        r.posUnit += 1;
        r.posUnit /= 2;
        r.posUnit.y = 1-r.posUnit.y;
        return r;
    }
}

namespace Clamp {
    using namespace metal;
    inline int Mirror(uint bound, int pt) {
        if (pt < 0) return -pt;
        if (pt >= (int)bound) return 2*((int)bound-1)-pt;
        return pt;
    }
    
    inline int2 Mirror(uint2 bound, int2 pt) {
        return {
            Mirror(bound.x, pt.x),
            Mirror(bound.y, pt.y)
        };
    }
}

namespace Sample {
    using namespace metal;
    // Edge clamp
    struct EdgeClampType {}; constant auto EdgeClamp = EdgeClampType();
    
    inline float3 RGB(EdgeClampType, texture2d<float> txt, int2 pos) {
        return txt.sample(coord::pixel, float2(pos.x+.5, pos.y+.5)).rgb;
    }
    
    inline float R(EdgeClampType, texture2d<float> txt, int2 pos) {
        return RGB(EdgeClamp, txt, pos).r;
    }
    
    // Mirror clamp
    struct MirrorClampType {}; constant auto MirrorClamp = MirrorClampType();
    
    inline float3 RGB(MirrorClampType, texture2d<float> txt, int2 pos) {
        const uint2 bounds(txt.get_width(), txt.get_height());
        return txt.sample(coord::pixel, float2(Clamp::Mirror(bounds, pos))+float2(.5,.5)).rgb;
    }
    
    inline float R(MirrorClampType, texture2d<float> txt, int2 pos) {
        return RGB(MirrorClamp, txt, pos).r;
    }
    
    // Default implementation calls EdgeClamp variant
    inline float3 RGB(texture2d<float> txt, int2 pos) {
        return RGB(EdgeClamp, txt, pos);
    }
    
    inline float R(texture2d<float> txt, int2 pos) {
        return R(EdgeClamp, txt, pos);
    }
};

#endif // MetalShaderContext

} // MetalUtil
} // CFAViewer
