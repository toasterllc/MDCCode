#import <metal_stdlib>
#import "FullSizeImageViewTypes.h"
#import "Tools/Shared/MetalUtil.h"
using namespace metal;
using namespace MDCTools::MetalUtil;
using namespace MDCStudio::FullSizeImageViewTypes;

namespace MDCStudio {
namespace FullSizeImageViewShader {

struct VertexOutput {
    float4 pos [[position]];
    float2 posUnit;
};

vertex VertexOutput ImageVertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    VertexOutput r = {
        .pos = ctx.transform * float4(SquareVert[vidx], 0, 1),
        .posUnit = SquareVertYFlipped[vidx],
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
