#import <metal_stdlib>
#import "FullSizeImageViewTypes.h"
#import "Tools/Shared/MetalUtil.h"
using namespace metal;
using namespace MDCTools::MetalUtil;
using namespace MDCStudio::ImageViewTypes;

namespace MDCStudio {
namespace ImageViewShader {

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

vertex VertexOutput VertexShader(
    constant float4x4& transform [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    VertexOutput r = {
        .pos = transform * float4(_Verts[vidx], 0, 1),
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

} // namespace ImageViewShader
} // namespace MDCStudio
