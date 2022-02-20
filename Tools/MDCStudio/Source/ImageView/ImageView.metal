#import <metal_stdlib>
#import "ImageViewTypes.h"
#import "Tools/Shared/MetalUtil.h"
using namespace metal;
using namespace MDCTools::MetalUtil;
using namespace MDCStudio::ImageViewTypes;

namespace MDCStudio {
namespace ImageViewShader {

struct VertexOutput {
    float4 pos [[position]];
    float2 posUnit;
};

static constexpr constant vector_float4 _ViewCoords[6] = {
    {-1, -1, 0, 1},
    {-1,  1, 0, 1},
    { 1, -1, 0, 1},
    { 1, -1, 0, 1},
    {-1,  1, 0, 1},
    { 1,  1, 0, 1},
};

vertex VertexOutput VertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    float4 pos = _ViewCoords[vidx];
    return VertexOutput{
        .pos = pos,
        .posUnit = pos.xy,
    };
}

fragment float4 FragmentShader(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
//    return float4(in.posUnit, 1, 1);
    return txt.sample({}, in.posUnit);
}

} // namespace ImageViewShader
} // namespace MDCStudio
