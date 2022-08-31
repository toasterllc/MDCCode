#import <metal_stdlib>
#import "../MetalUtil.h"
#import "ImagePipelineTypes.h"
using namespace metal;
using namespace MDCTools::MetalUtil;
using namespace MDCStudio::ImagePipeline;

namespace MDCStudio {
namespace ImagePipeline {
namespace Shader {
namespace LocalContrast {

fragment float ExtractL(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    return Sample::R(txt, int2(in.pos.xy));
}

fragment float4 LocalContrast(
    constant float& amount [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    texture2d<float> blurredLTxt [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const float blurredL = Sample::R(blurredLTxt, int2(in.pos.xy));
    float3 Lab = Sample::RGB(txt, int2(in.pos.xy));
    Lab[0] += (Lab[0]-blurredL)*amount;
    return float4(Lab, 1);
}

} // namespace LocalContrast
} // namespace Shader
} // namespace ImagePipeline
} // namespace MDCStudio
