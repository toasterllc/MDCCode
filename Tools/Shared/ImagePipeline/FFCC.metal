#import <metal_stdlib>
#import "Code/Lib/Toastbox/Mac/MetalUtil.h"
#import "Code/Lib/Toastbox/Mac/Mod.h"
#import "Code/Lib/Toastbox/Mac/CFA.h"
using namespace metal;
using namespace Toastbox;
using namespace Toastbox::MetalUtil;

namespace FFCC {

fragment float CreateMask(
    texture2d<float> img [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float3 s = Sample::RGB(img, pos);
    #warning TODO: we should mask out highlights too right?
    // If any of the pixels are 0, the mask is 0
    if (s.r==0 || s.g==0 || s.b==0) return 0;
    // Otherwise the mask is 1
    return 1;
}

fragment float4 ApplyMask(
    texture2d<float> img [[texture(0)]],
    texture2d<float> mask [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float3 s = Sample::RGB(img, pos);
    const float m = Sample::R(mask, pos);
    return float4(m*s,1);
}

fragment float LocalAbsoluteDeviationCoeff(
    texture2d<float> mask [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
#define M(x,y) Sample::R(mask, pos+int2{x,y})
    return M(0,0) / (
        M(-1,-1) + M(0,-1) + M(1,-1) +
        M(-1, 0) +         + M(1, 0) +
        M(-1, 1) + M(0, 1) + M(1, 1) );
#undef M
}

fragment float4 LocalAbsoluteDeviation(
    texture2d<float> img [[texture(0)]],
    texture2d<float> mask [[texture(1)]],
    texture2d<float> coeff [[texture(2)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
#define M(x,y) Sample::R(mask, pos+int2{x,y})
#define I(x,y) Sample::RGB(img, pos+int2{x,y})
#define S(x,y) (M(x,y) * abs(I(x,y)-sc))
    const float3 sc = I(0,0);
    const float3 s =
        S(-1,-1) + S(0,-1) + S(1,-1) +
        S(-1, 0) +         + S(1, 0) +
        S(-1, 1) + S(0, 1) + S(1, 1) ;
#undef S
#undef I
#undef M
    const float k = Sample::R(coeff, pos);
    return float4(k*s, 1);
}

fragment float CalcU(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float3 s = Sample::RGB(txt, pos);
    if (s.g==0 || s.r==0) return 0;
    return log(s.g)-log(s.r);
}

fragment float CalcV(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float3 s = Sample::RGB(txt, pos);
    if (s.g==0 || s.b==0) return 0;
    return log(s.g)-log(s.b);
}

fragment float CalcMaskUV(
    constant float& thresh [[buffer(0)]],
    device atomic_uint* validPixelCount [[buffer(1)]],
    texture2d<float> img [[texture(0)]],
    texture2d<float> mask [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float sm = Sample::R(mask, pos);
    if (sm == 0) return 0;
    const float3 si = Sample::RGB(img, pos);
    if (si.r<thresh || si.g<thresh || si.b<thresh) return 0;
    atomic_fetch_add_explicit(validPixelCount, 1, memory_order_relaxed);
    return 1;
}

fragment float CalcBinUV(
    constant uint32_t& binCount [[buffer(0)]],
    constant float& binSize [[buffer(1)]],
    constant float& binMin [[buffer(2)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float s = Sample::R(txt, pos);
    return 1 + Mod(round((s-binMin)/binSize), (float)binCount);
}

uint32_t binForPos(uint32_t binCount, uint32_t y, uint32_t x) {
    return x*binCount + y; // Column-major layout
}

fragment void CalcHistogram(
    constant uint32_t& binCount [[buffer(0)]],
    device atomic_uint* bins [[buffer(1)]],
    texture2d<float> u [[texture(0)]],
    texture2d<float> v [[texture(1)]],
    texture2d<float> mask [[texture(2)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float m = Sample::R(mask, pos);
    // Ignore this pixel if it's masked
    if (m == 0) return;
    const uint32_t y = round(Sample::R(u, pos)-1);
    const uint32_t x = round(Sample::R(v, pos)-1);
    const uint32_t bin = binForPos(binCount, y, x);
    atomic_fetch_add_explicit(&bins[bin], 1, memory_order_relaxed);
}

fragment float LoadHistogram(
    constant uint32_t& binCount [[buffer(0)]],
    constant uint32_t* bins [[buffer(1)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const uint32_t bin = binForPos(binCount, pos.y, pos.x);
    return (float)bins[bin];
}

fragment float NormalizeHistogram(
    constant uint32_t& validPixelCount [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    constexpr float Eps = 1e-6;
    const int2 pos = int2(in.pos.xy);
    const float s = Sample::R(txt, pos);
    return s / max(Eps, (float)validPixelCount);
}

fragment float Transpose(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    return Sample::R(txt, pos.yx);
}

fragment float4 Scale(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    return float4(txt.sample({filter::linear}, in.posUnit).rgb, 1);
}

#define PX(x,y) Sample::R(Sample::MirrorClamp, raw, pos+int2{x,y})
float r(constant CFADesc& cfaDesc, texture2d<float> raw, int2 pos) {
    const CFAColor c = cfaDesc.color(pos);
    const CFAColor cn = cfaDesc.color(pos.x+1, pos.y);
    if (c==CFAColor::Blue || cn==CFAColor::Blue) {
        // ROW = B G B G ...
        
        // Have G
        // Want R
        // Sample @ y-1, y+1
        if (c == CFAColor::Green) return .5*PX(+0,-1) + .5*PX(+0,+1);
        
        // Have B
        // Want R
        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
        else return .25*PX(-1,-1) + .25*PX(-1,+1) + .25*PX(+1,-1) + .25*PX(+1,+1);
    
    } else {
        // ROW = G R G R ...
        
        // Have G
        // Want R
        // Sample @ x-1 and x+1
        if (c == CFAColor::Green) return .5*PX(-1,+0) + .5*PX(+1,+0);
        
        // Have R
        // Want R
        // Sample @ this pixel
        else return PX(+0,+0);
    }
}

float g(constant CFADesc& cfaDesc, texture2d<float> raw, int2 pos) {
    const CFAColor c = cfaDesc.color(pos);
    const CFAColor cn = cfaDesc.color(pos.x+1, pos.y);
    if (c==CFAColor::Blue || cn==CFAColor::Blue) {
        // ROW = B G B G ...
        
        // Have G
        // Want G
        // Sample @ this pixel
        if (c == CFAColor::Green) return PX(+0,+0);
        
        // Have B
        // Want G
        // Sample @ x-1, x+1, y-1, y+1
        else return .25*PX(-1,+0) + .25*PX(+1,+0) + .25*PX(+0,-1) + .25*PX(+0,+1) ;
    
    } else {
        // ROW = G R G R ...
        
        // Have G
        // Want G
        // Sample @ this pixel
        if (c == CFAColor::Green) return PX(+0,+0);
        
        // Have R
        // Want G
        // Sample @ x-1, x+1, y-1, y+1
        else return .25*PX(-1,+0) + .25*PX(+1,+0) + .25*PX(+0,-1) + .25*PX(+0,+1) ;
    }
}

float b(constant CFADesc& cfaDesc, texture2d<float> raw, int2 pos) {
    const CFAColor c = cfaDesc.color(pos);
    const CFAColor cn = cfaDesc.color(pos.x+1, pos.y);
    if (c==CFAColor::Blue || cn==CFAColor::Blue) {
        // ROW = B G B G ...
        
        // Have G
        // Want B
        // Sample @ x-1, x+1
        if (c == CFAColor::Green) return .5*PX(-1,+0) + .5*PX(+1,+0);
        
        // Have B
        // Want B
        // Sample @ this pixel
        else return PX(+0,+0);
    
    } else {
        // ROW = G R G R ...
        
        // Have G
        // Want B
        // Sample @ y-1, y+1
        if (c == CFAColor::Green) return .5*PX(+0,-1) + .5*PX(+0,+1);
        
        // Have R
        // Want B
        // Sample @ {-1,-1}, {-1,+1}, {+1,-1}, {+1,+1}
        else return .25*PX(-1,-1) + .25*PX(-1,+1) + .25*PX(+1,-1) + .25*PX(+1,+1) ;
    }
}
#undef PX

fragment float4 Debayer(
    constant CFADesc& cfaDesc [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    return float4(r(cfaDesc, raw, pos), g(cfaDesc, raw, pos), b(cfaDesc, raw, pos), 1);
}

} // namespace FFCC
