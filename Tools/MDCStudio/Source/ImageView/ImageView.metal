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
//
//static constexpr constant vector_float4 _ViewCoords[6] = {
//    {-1, -1, 0, 1},
//    {-1,  1, 0, 1},
//    { 1, -1, 0, 1},
//    { 1, -1, 0, 1},
//    {-1,  1, 0, 1},
//    { 1,  1, 0, 1},
//};
//
//vertex VertexOutput VertexShader(
//    constant RenderContext& ctx [[buffer(0)]],
//    uint vidx [[vertex_id]]
//) {
//    float4 pos = _ViewCoords[vidx];
//    return VertexOutput{
//        .pos = pos,
//        .posUnit = pos.xy,
//    };
//}

fragment float4 FragmentShader(
    constant int2& off [[buffer(0)]],
    constant float4& backgroundColor [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    int2 pos = int2(in.pos.xy);
    if (pos.x < off.x                           ||
        pos.y < off.y                           ||
        pos.x >= (off.x+(int)txt.get_width())   ||
        pos.y >= (off.y+(int)txt.get_height())  )
        return backgroundColor;
    
    return Sample::RGBA(txt, pos-off);
}

} // namespace ImageViewShader
} // namespace MDCStudio
