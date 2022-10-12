#pragma once
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
#define MetalConstant constant
#define MetalDevice device
#define MetalThread thread
#else
#define MetalConstant
#define MetalDevice
#define MetalThread
#endif

namespace MDCTools {
namespace MetalUtil {

// Unique vertexes (defines a unit square)
constexpr MetalConstant vector_float4 SquareVert[4] = {
    { 1,  1, 0, 1},
    {-1,  1, 0, 1},
    {-1, -1, 0, 1},
    { 1, -1, 0, 1},
};

// Vertex indicies (for a square)
constexpr MetalConstant uint8_t SquareVertIdx[6] = {
    0, 1, 2,
    0, 2, 3,
};

constexpr MetalConstant size_t SquareVertIdxCount = sizeof(SquareVertIdx)/sizeof(*SquareVertIdx);

#if MetalShaderContext

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
    
    inline float4 RGBA(EdgeClampType, texture2d<float> txt, int2 pos) {
        return txt.sample(coord::pixel, float2(pos.x+.5, pos.y+.5));
    }
    
    inline float3 RGB(EdgeClampType, texture2d<float> txt, int2 pos) {
        return RGBA(EdgeClamp, txt, pos).rgb;
    }
    
    inline float2 RG(EdgeClampType, texture2d<float> txt, int2 pos) {
        return RGBA(EdgeClamp, txt, pos).rg;
    }
    
    inline float R(EdgeClampType, texture2d<float> txt, int2 pos) {
        return RGBA(EdgeClamp, txt, pos).r;
    }
    
    // Mirror clamp
    struct MirrorClampType {}; constant auto MirrorClamp = MirrorClampType();
    
    inline float4 RGBA(MirrorClampType, texture2d<float> txt, int2 pos) {
        const uint2 bounds(txt.get_width(), txt.get_height());
        return txt.sample(coord::pixel, float2(Clamp::Mirror(bounds, pos))+float2(.5,.5));
    }
    
    inline float3 RGB(MirrorClampType, texture2d<float> txt, int2 pos) {
        return RGBA(MirrorClamp, txt, pos).rgb;
    }
    
    inline float2 RG(MirrorClampType, texture2d<float> txt, int2 pos) {
        return RGBA(MirrorClamp, txt, pos).rg;
    }
    
    inline float R(MirrorClampType, texture2d<float> txt, int2 pos) {
        return RGBA(MirrorClamp, txt, pos).r;
    }
    
    // Default implementation calls EdgeClamp variant
    inline float4 RGBA(texture2d<float> txt, int2 pos) {
        return RGBA(EdgeClamp, txt, pos);
    }
    
    inline float3 RGB(texture2d<float> txt, int2 pos) {
        return RGB(EdgeClamp, txt, pos);
    }
    
    inline float2 RG(texture2d<float> txt, int2 pos) {
        return RG(EdgeClamp, txt, pos);
    }
    
    inline float R(texture2d<float> txt, int2 pos) {
        return R(EdgeClamp, txt, pos);
    }
};

#endif // MetalShaderContext

} // namespace MetalUtil
} // namespace MDCTools
