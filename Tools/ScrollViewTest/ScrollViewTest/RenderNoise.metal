#import <metal_stdlib>
#import "Tools/Shared/MetalUtil.h"
using namespace metal;
using namespace MDCTools::MetalUtil;

fragment float4 RenderNoise(
    constant uint32_t& tileSize,
    device uint8_t* noiseData,
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const uint32_t off = 3*((pos.y*tileSize + pos.x));
    const float3 noise(
        (noiseData[off+0] / 255.f),
        (noiseData[off+0] / 255.f),
        (noiseData[off+0] / 255.f)
    );
    
    return float4(noise, .001);
    
//    return float4(bg, 1);
//    return float4(.5, 0, 0, 1);
//    return float4(randColor, 1);
//    return txt.sample({}, in.posUnit)/10;
//    return txt.sample(coord::pixel, float2(in.pos.x, in.pos.y));
//    return float4(txt.sample({}, in.pos.xy), 1);
//    return float4(txt.sample({}, in.pos.xy).rgb, 1);
//    if ((int)in.pos.y & 0x1) {
//        return float4(1,1,1,1);
//    }
//    return float4(0,0,0,1);
}
