#import <metal_stdlib>
#import "MetalUtil.h"
#import "ImagePipelineTypes.h"
using namespace metal;
using namespace CFAViewer::MetalUtil;
using namespace CFAViewer::MetalUtil::Standard;
using namespace CFAViewer::ImagePipeline;

namespace CFAViewer {
namespace Shader {
namespace ImagePipeline {

fragment float ReconstructHighlights(
    constant CFADesc& cfaDesc [[buffer(0)]],
    constant float3& badPixelFactors [[buffer(1)]],
    constant float3& goodPixelFactors [[buffer(2)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float Thresh = 1;
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = cfaDesc.color(pos);
    const float s = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+0});
    const float l = Sample::R(Sample::MirrorClamp, raw, pos+int2{-1,+0});
    const float r = Sample::R(Sample::MirrorClamp, raw, pos+int2{+1,+0});
    const float u = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,-1});
    const float d = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+1});
    
    // Pass-through if this pixel isn't saturated
    if (s < Thresh) return s;
    
    const uint good = (l<Thresh) + (r<Thresh) + (u<Thresh) + (d<Thresh);
    if (good == 0) {
        switch (c) {
        case CFAColor::Red:     return badPixelFactors.r*s;
        case CFAColor::Green:   return badPixelFactors.g*s;
        case CFAColor::Blue:    return badPixelFactors.b*s;
        }
    }
    
    const float x̄ = (l+r+u+d)/4;
    switch (c) {
    case CFAColor::Red:     return goodPixelFactors.r*x̄;
    case CFAColor::Green:   return goodPixelFactors.g*x̄;
    case CFAColor::Blue:    return goodPixelFactors.b*x̄;
    }
}

} // namespace ImagePipeline
} // namespace Shader
} // namespace CFAViewer
