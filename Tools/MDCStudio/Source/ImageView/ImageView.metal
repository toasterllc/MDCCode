#import <metal_stdlib>
#import "ImageViewTypes.h"
#import "Tools/Shared/MetalUtil.h"
using namespace metal;
using namespace MDCTools::MetalUtil;
using namespace MDCStudio::ImageViewTypes;

namespace MDCStudio {
namespace ImageViewShader {

//struct VertexOutput {
//    float4 pos [[position]];
//    float2 posUnit;
//};

//static constexpr constant vector_float4 _ViewCoords[6] = {
//    {-1, -1, 0, 1},
//    {-1,  1, 0, 1},
//    { 1, -1, 0, 1},
//    { 1, -1, 0, 1},
//    {-1,  1, 0, 1},
//    { 1,  1, 0, 1},
//};

static constexpr constant vector_float4 _ViewCoords[6] = {
    {0,     0,      0, 1},
    {0,     1296,   0, 1},
    {2304,  0,      0, 1},
    {2304,  0,      0, 1},
    {0,     1296,   0, 1},
    {2304,  1296,   0, 1},
};

vertex VertexOutput VertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    VertexOutput r = {
        .pos = ctx.viewMatrix * _ViewCoords[vidx],
        .posUnit = _ViewCoords[vidx].xy / float2(2304,1296),
    };
    
//    r.posUnit = r.pos.xy;
//    r.posUnit += 1;
//    r.posUnit /= 2;
//    r.posUnit.y = 1-r.posUnit.y;
    return r;
}

fragment float4 FragmentShader(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    return txt.sample({}, in.posUnit);
//    return txt.sample(coord::pixel, float2(in.pos.x, in.pos.y));
//    return float4(txt.sample({}, in.pos.xy), 1);
//    return float4(txt.sample({}, in.pos.xy).rgb, 1);
    return float4(.1,0,0,1);
}

//fragment float4 FragmentShader(
//    constant int2& off [[buffer(0)]],
//    constant float4& backgroundColor [[buffer(1)]],
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    int2 pos = int2(in.pos.xy);
//    if (pos.x < off.x                           ||
//        pos.y < off.y                           ||
//        pos.x >= (off.x+(int)txt.get_width())   ||
//        pos.y >= (off.y+(int)txt.get_height())  )
//        return backgroundColor;
//    
//    return Sample::RGBA(txt, pos-off);
//}

} // namespace ImageViewShader
} // namespace MDCStudio
