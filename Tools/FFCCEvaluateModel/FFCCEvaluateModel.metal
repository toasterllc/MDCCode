#import <metal_stdlib>
#import "MetalUtil.h"
#import "ImagePipelineTypes.h"
using namespace metal;
using namespace CFAViewer::MetalUtil;
using namespace CFAViewer::MetalUtil::Standard;

fragment float4 LoadImage(
    constant uint32_t& w [[buffer(0)]],
    constant uint32_t& h [[buffer(1)]],
    constant uint16_t* pxs [[buffer(2)]],
    VertexOutput in [[stage_in]]
) {
    const uint32_t SamplesPerPixel = 4;
    const int2 pos = int2(in.pos.xy);
    return float4(
        (float)pxs[SamplesPerPixel*(w*pos.y + pos.x) + 0] / 0xFFFF,
        (float)pxs[SamplesPerPixel*(w*pos.y + pos.x) + 1] / 0xFFFF,
        (float)pxs[SamplesPerPixel*(w*pos.y + pos.x) + 2] / 0xFFFF,
        1
    );
}

fragment float4 MaskedLocalAbsoluteDeviation(
    texture2d<float> img [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
#define PX(x,y) Sample::RGB(img, pos+int2{x,y})
    const float3 s = PX(0,0);
    const float3 Σ = 
        abs(PX(-1,-1)-s) + abs(PX( 0,-1)-s) + abs(PX( 1,-1)-s) +
        abs(PX(-1, 0)-s) +                  + abs(PX( 1, 0)-s) +
        abs(PX(-1, 1)-s) + abs(PX( 0, 1)-s) + abs(PX( 1, 1)-s) ;
    return float4(Σ,1) / 8;
#undef PX
}
