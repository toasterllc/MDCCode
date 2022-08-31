#import <metal_stdlib>
#import "Tools/Shared/MetalUtil.h"
#import "ImagePipelineTypes.h"
#import "Tools/Shared/CFA.h"
using namespace metal;
using namespace MDCStudio;
using namespace MDCStudio::ImagePipeline;
using namespace MDCTools::MetalUtil;

namespace MDCStudio {
namespace ImagePipeline {
namespace Shader {

fragment float DownsampleLoad(
    constant int32_t& downsampleFactor [[buffer(0)]],
    texture2d<float> rawLarge [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const int2 p = downsampleFactor*((pos/2)*2) + pos%2;
    return Sample::R(rawLarge, p);
    
//    return Sample::R(rawLarge, int2(in.pos.xy));
}

} // namespace Shader
} // namespace ImagePipeline
} // namespace MDCStudio
