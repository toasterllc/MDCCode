#import <metal_stdlib>
#import "FullSizeImageViewTypes.h"
#import "Tools/Shared/MetalUtil.h"
using namespace metal;
using namespace MDCTools::MetalUtil;
using namespace MDCStudio::FullSizeImageViewTypes;

namespace MDCStudio {
namespace FullSizeImageViewShader {

static constexpr constant float2 _Verts[6] = {
    {0, 0},
    {0, 1},
    {1, 0},
    {1, 0},
    {0, 1},
    {1, 1},
};

struct VertexOutput {
    float4 pos [[position]];
    float2 posUnit;
};

vertex VertexOutput ImageVertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    VertexOutput r = {
        .pos = ctx.transform * float4(_Verts[vidx], 0, 1),
        .posUnit = _Verts[vidx],
    };
    return r;
}

vertex VertexOutput TimestampVertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    const float2 v = ((_Verts[vidx] * ctx.timestampSize) * 2) - 1;
    VertexOutput r = {
        .pos = float4(v, 0, 1),
        .posUnit = _Verts[vidx],
    };
    return r;
}

fragment float4 FragmentShader(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    return txt.sample({}, in.posUnit);
}

} // namespace FullSizeImageViewShader
} // namespace MDCStudio
