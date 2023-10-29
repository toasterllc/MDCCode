#pragma once
#import <simd/simd.h>

#ifdef __METAL_VERSION__
#define MetalShaderContext 1
#else
#define MetalShaderContext 0
#endif

#if !MetalShaderContext
#import <atomic>
#import <string>
#import <Metal/Metal.h>
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

constexpr MetalConstant simd::float2 SquareVert[6] = {
    {0, 0},
    {0, 1},
    {1, 0},
    {1, 0},
    {0, 1},
    {1, 1},
};

constexpr MetalConstant simd::float2 SquareVertYFlipped[6] = {
    {0, 1},
    {0, 0},
    {1, 1},
    {1, 1},
    {0, 0},
    {1, 0},
};

constexpr MetalConstant size_t SquareVertCount = sizeof(SquareVert)/sizeof(*SquareVert);

#if MetalShaderContext

struct VertexOutput {
    float4 pos [[position]];
    float2 posUnit;
};

inline VertexOutput VertexShader(uint vidx) {
    VertexOutput r = {
        .pos = float4((2*SquareVert[vidx])-1, 0, 1),
        .posUnit = SquareVertYFlipped[vidx],
    };
    return r;
}

inline float4 FragmentShader(metal::texture2d<float> txt, VertexOutput in) {
    return txt.sample({}, in.posUnit);
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

#if !MetalShaderContext

// MTLLibraryReturnsAutoreleasedFix:
// We're seeing crashes on macOS 10.15.7 which appear to be because -newFunctionWithName:
// returns an autoreleased object, but ARC expects a retained object because the method
// starts with 'new'.
// So we correct the issue by decorating the method appropriately with `ns_returns_not_retained`.
// In the future this will cause a leak if Apple decides to fix the bug by making
// -newFunctionWithName return a retained object.
// Alternatively, things will work correctly if Apple fixes the bug by marking their
// method with `ns_returns_not_retained`
@protocol MTLLibraryReturnsAutoreleasedFix
- (id<MTLFunction>)newFunctionWithName:(NSString*)functionName __attribute__((ns_returns_not_retained));
@end

namespace MDCTools::MetalUtil {

inline id<MTLFunction> MTLFunctionWithName(id<MTLLibrary> lib, std::string_view name) {
    id<MTLLibraryReturnsAutoreleasedFix> l = (id)lib;
    return [l newFunctionWithName:@(name.data())];
}

}

#endif
