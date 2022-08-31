#import <metal_stdlib>
#import "../MetalUtil.h"
using namespace metal;
using namespace MDCTools::MetalUtil;

namespace MDCTools {
namespace ImagePipeline {
namespace Shader {
namespace RenderThumb {

fragment void RGB3FromTexture(
    constant uint32_t& dataOff [[buffer(0)]],
    constant uint32_t& thumbWidth [[buffer(1)]],
    device uint8_t* dst [[buffer(2)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const uint pxIdx = (pos.y*thumbWidth + pos.x);
    const uint32_t off = dataOff + (3 * pxIdx);
    const float3 s = Sample::RGB(txt, pos);
//    dst[off+0] = s.r*255;
//    dst[off+1] = s.g*255;
//    dst[off+2] = s.b*255;
    dst[off+0] = saturate(s.r)*255;
    dst[off+1] = saturate(s.g)*255;
    dst[off+2] = saturate(s.b)*255;
}

fragment float4 TextureFromRGB3(
    constant uint32_t& dataOff [[buffer(0)]],
    constant uint32_t& thumbWidth [[buffer(1)]],
    device uint8_t* src [[buffer(2)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const uint pxIdx = (pos.y*thumbWidth + pos.x);
    const uint32_t off = dataOff + (3 * pxIdx);
    return float4(
        (float)src[off+0]/255,
        (float)src[off+1]/255,
        (float)src[off+2]/255,
        1
    );
}




} // namespace RenderThumb
} // namespace Shader
} // namespace ImagePipeline
} // namespace MDCTools
