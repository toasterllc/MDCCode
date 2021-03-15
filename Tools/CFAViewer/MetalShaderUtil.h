#import <metal_stdlib>
using namespace metal;
static_assert(__METAL_VERSION__, "Only usable from Metal shader context");

struct VertexOutput {
    float4 pos [[position]];
    float2 posUnit;
};

namespace Clamp {
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
