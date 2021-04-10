#import <metal_stdlib>
#import "MetalUtil.h"
#import "ImagePipelineTypes.h"
#import "Mod.h"
using namespace metal;
using namespace CFAViewer::MetalUtil;
using namespace CFAViewer::MetalUtil::Standard;

fragment float CreateMask(
    texture2d<float> img [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float3 s = Sample::RGB(img, pos);
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



//fragment float4 Log(
//    texture2d<float> img [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const int2 pos = int2(in.pos.xy);
//    const float3 s = Sample::RGB(img, pos);
//    return float4(log(s), 1);
//}

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
    texture2d<float> img [[texture(0)]],
    texture2d<float> mask [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float sm = Sample::R(mask, pos);
    if (sm == 0) return 0;
    const float3 si = Sample::RGB(img, pos);
    if (si.r<thresh || si.g<thresh || si.b<thresh) return 0;
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
    const uint32_t y = round(Sample::R(u, pos));
    const uint32_t x = round(Sample::R(v, pos));
    const uint32_t i = (x-1)*binCount + (y-1); // Column-major index into `bins`
    atomic_fetch_add_explicit(&bins[i], 1, memory_order_relaxed);
}

//fragment float CreateUVMask(
//    texture2d<float> u [[texture(0)]],
//    texture2d<float> v [[texture(1)]],
//    VertexOutput in [[stage_in]]
//) {
//    const int2 pos = int2(in.pos.xy);
//    const float3 su = Sample::R(u, pos);
//    const float3 sv = Sample::R(v, pos);
//    
//    // If any of the pixels are 0, the mask is 0
//    if (s.r==0 || s.g==0 || s.b==0) return 0;
//    // Otherwise the mask is 1
//    return 1;
//}




//fragment float4 MaskedLocalAbsoluteDeviation(
//    texture2d<float> img [[texture(0)]],
//    texture2d<float> mask [[texture(1)]],
//    VertexOutput in [[stage_in]]
//) {
//    const int2 pos = int2(in.pos.xy);
//    
//#define S(x,y) Sample::RGB(img, pos+int2{x,y})
//    const float3 s[3][3] = {
//        { S(-1,-1) , S(0,-1) , S(1,-1) } ,
//        { S(-1, 0) , S(0, 0) , S(1, 0) } ,
//        { S(-1, 1) , S(0, 1) , S(1, 1) } ,
//    };
//#undef S
//    
//#define M(x,y) Sample::R(mask, pos+int2{x,y})
//    const float m[3][3] = {
//        { M(-1,-1) , M(0,-1) , M(1,-1) } ,
//        { M(-1, 0) , M(0, 0) , M(1, 0) } ,
//        { M(-1, 1) , M(0, 1) , M(1, 1) } ,
//    };
//#undef M
//    
//#define S(x,y) s[1+(y)][1+(x)]
//#define M(x,y) m[1+(y)][1+(x)]
//    const float3 sc = S(0,0);
//    const float3 numer = M(0,0) * (
//        (M(-1,-1)*abs(S(-1,-1)-sc)) + (M(0,-1)*abs(S(0,-1)-sc)) + (M(1,-1)*abs(S(1,-1)-sc)) +
//        (M(-1, 0)*abs(S(-1, 0)-sc)) +                           + (M(1, 0)*abs(S(1, 0)-sc)) +
//        (M(-1, 1)*abs(S(-1, 1)-sc)) + (M(0, 1)*abs(S(0, 1)-sc)) + (M(1, 1)*abs(S(1, 1)-sc)) 
//    );
//    
//    const float denom = (
//        (M(-1,-1)) + (M(0,-1)) + (M(1,-1)) +
//        (M(-1, 0)) +           + (M(1, 0)) +
//        (M(-1, 1)) + (M(0, 1)) + (M(1, 1))
//    );
//#undef M
//#undef S
//    
//    return float4(numer/denom, 1);
//}
