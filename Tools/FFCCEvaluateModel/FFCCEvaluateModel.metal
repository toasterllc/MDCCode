#import <metal_stdlib>
#import "MetalUtil.h"
#import "ImagePipelineTypes.h"
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
    return float4(s*m,1);
}

fragment float4 MaskedLocalAbsoluteDeviation(
    texture2d<float> img [[texture(0)]],
    texture2d<float> mask [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    
#define S(x,y) Sample::RGB(img, pos+int2{x,y})
    const float3 s[3][3] = {
        { S(-1,-1) , S(0,-1) , S(1,-1) } ,
        { S(-1, 0) , S(0, 0) , S(1, 0) } ,
        { S(-1, 1) , S(0, 1) , S(1, 1) } ,
    };
#undef S
    
#define M(x,y) Sample::R(mask, pos+int2{x,y})
    const float m[3][3] = {
        { M(-1,-1) , M(0,-1) , M(1,-1) } ,
        { M(-1, 0) , M(0, 0) , M(1, 0) } ,
        { M(-1, 1) , M(0, 1) , M(1, 1) } ,
    };
#undef M
    
#define S(x,y) s[1+(y)][1+(x)]
#define M(x,y) m[1+(y)][1+(x)]
    const float3 sc = S(0,0);
    const float3 numer = M(0,0) * (
        (M(-1,-1)*abs(S(-1,-1)-sc)) + (M(0,-1)*abs(S(0,-1)-sc)) + (M(1,-1)*abs(S(1,-1)-sc)) +
        (M(-1, 0)*abs(S(-1, 0)-sc)) +                           + (M(1, 0)*abs(S(1, 0)-sc)) +
        (M(-1, 1)*abs(S(-1, 1)-sc)) + (M(0, 1)*abs(S(0, 1)-sc)) + (M(1, 1)*abs(S(1, 1)-sc)) 
    );
    
    const float3 denom = (
        (M(-1,-1)) + (M(0,-1)) + (M(1,-1)) +
        (M(-1, 0)) +           + (M(1, 0)) +
        (M(-1, 1)) + (M(0, 1)) + (M(1, 1))
    );
#undef M
#undef S
    
    return float4(numer/denom, 1);

//    const float3 num =
//        abs(PX(-1,-1)-s) + abs(PX( 0,-1)-s) + abs(PX( 1,-1)-s) +
//        abs(PX(-1, 0)-s)                    + abs(PX( 1, 0)-s) +
//        abs(PX(-1, 1)-s) + abs(PX( 0, 1)-s) + abs(PX( 1, 1)-s) ;
//    

//    
//    
//    
//    
//    
//    
//#define PX(x,y) s[1+(y)][1+(x)]
//#define PXVALID(x,y) (PX(x,y).r!=0 && PX(x,y).g!=0 && PX(x,y).b!=0)
//    if (!PXVALID(0,0)) return 0;
//    
//    const float3 num =
//        abs(PX(-1,-1)-s) + abs(PX( 0,-1)-s) + abs(PX( 1,-1)-s) +
//        abs(PX(-1, 0)-s) +                  + abs(PX( 1, 0)-s) +
//        abs(PX(-1, 1)-s) + abs(PX( 0, 1)-s) + abs(PX( 1, 1)-s) ;
//#undef PXVALID
//#undef PX
//    
//#define PX(x,y) s[1+(y)][1+(x)]
//    const float3 denom =
//        abs(PX(-1,-1)-s) + abs(PX( 0,-1)-s) + abs(PX( 1,-1)-s) +
//        abs(PX(-1, 0)-s) +                  + abs(PX( 1, 0)-s) +
//        abs(PX(-1, 1)-s) + abs(PX( 0, 1)-s) + abs(PX( 1, 1)-s) ;
//    
//    const float3 s[3][3] = {{1 , 2 , 3 },
//        {1 , 2 , 3 },
//        {1 , 2 , 3 },
//    };
//    
//    
//    const float3 num =
//        abs(PX(-1,-1)-s) + abs(PX( 0,-1)-s) + abs(PX( 1,-1)-s) +
//        abs(PX(-1, 0)-s) +                  + abs(PX( 1, 0)-s) +
//        abs(PX(-1, 1)-s) + abs(PX( 0, 1)-s) + abs(PX( 1, 1)-s) ;
//    
//    const float3 denom =
//        abs(PX(-1,-1)-s) + abs(PX( 0,-1)-s) + abs(PX( 1,-1)-s) +
//        abs(PX(-1, 0)-s) +                  + abs(PX( 1, 0)-s) +
//        abs(PX(-1, 1)-s) + abs(PX( 0, 1)-s) + abs(PX( 1, 1)-s) ;
//    
//    const float3 Σ =
//        abs(PX(-1,-1)-s) + abs(PX( 0,-1)-s) + abs(PX( 1,-1)-s) +
//        abs(PX(-1, 0)-s) +                  + abs(PX( 1, 0)-s) +
//        abs(PX(-1, 1)-s) + abs(PX( 0, 1)-s) + abs(PX( 1, 1)-s) ;
//    return float4(Σ,1) / 8;
//#undef PX
}
