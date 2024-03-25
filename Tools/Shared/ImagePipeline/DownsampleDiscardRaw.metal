#import <metal_stdlib>
#import "ImagePipelineTypes.h"
#import "../CFA.h"
#import "Code/Lib/Toastbox/Mac/MetalUtil.h"
using namespace metal;
using namespace MDCTools;
using namespace MDCTools::ImagePipeline;
using namespace Toastbox::MetalUtil;

namespace MDCTools {
namespace ImagePipeline {
namespace Shader {

// DownsampleDiscardRaw: downsample raw image by discarding data (instead of resampling)
fragment float DownsampleDiscardRaw(
    constant int32_t& factor [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const int2 p = factor*((pos/2)*2) + pos%2;
    return Sample::R(raw, p);
}

} // namespace Shader
} // namespace ImagePipeline
} // namespace MDCTools
