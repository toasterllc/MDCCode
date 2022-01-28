#import <metal_stdlib>
#import "MetalUtil.h"
#import "RenderThumbTypes.h"
using namespace metal;
using namespace CFAViewer::MetalUtil;
using namespace CFAViewer::MetalUtil::Standard;

fragment void RenderThumb(
    constant RenderContext& ctx [[buffer(0)]],
    device uint8_t* dst [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const uint pxIdx = (pos.y*ctx.width + pos.x);
    const uint32_t off = ctx.thumbOff + (RenderContext::BytesPerPixel * pxIdx);
    const float3 s = Sample::RGB(txt, pos);
    dst[off+0] = s.r*255;
    dst[off+1] = s.g*255;
    dst[off+2] = s.b*255;
}


//fragment float4 ReadThumb(
//    constant RenderContext& ctx [[buffer(0)]],
//    device uint8_t* dst [[buffer(1)]],
//    VertexOutput in [[stage_in]]
//) {
//    const int2 pos = int2(in.pos.xy);
//    const uint pxIdx = (pos.y*ctx.width + pos.x);
////    const uint64_t thumbOff = U64FromVector(ctx.thumbOff);
//    const uint32_t off = ctx.thumbOff + (RenderContext::BytesPerPixel * pxIdx);
//    return float4(
//        (float)dst[off+0] / 255,
//        (float)dst[off+1] / 255,
//        (float)dst[off+2] / 255,
//        1
//    );
//}
