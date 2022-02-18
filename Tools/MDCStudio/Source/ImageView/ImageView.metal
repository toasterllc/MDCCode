#import <metal_stdlib>
#import "ImageViewTypes.h"
#import "Tools/Shared/MetalUtil.h"
using namespace metal;
using namespace MDCTools::MetalUtil;
using namespace MDCStudio::ImageViewTypes;

namespace MDCStudio {
namespace ImageViewShader {

struct VertexOutput {
    float4 posView [[position]];
    float2 posPx;
};

vertex VertexOutput VertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    return VertexOutput{
        .posView = 0,
        .posPx = 0,
    };
}

fragment float4 FragmentShader(
    constant RenderContext& ctx [[buffer(0)]],
    VertexOutput in [[stage_in]]
) {
    return 1;
}

} // namespace ImageViewShader
} // namespace MDCStudio
