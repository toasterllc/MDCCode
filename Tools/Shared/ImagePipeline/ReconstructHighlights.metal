#import <metal_stdlib>
#import "../MetalUtil.h"
#import "ImagePipelineTypes.h"
#import "../CFA.h"
using namespace metal;
using namespace MDCTools;
using namespace MDCTools::ImagePipeline;
using namespace MDCTools::MetalUtil;

namespace MDCTools {
namespace ImagePipeline {
namespace Shader {
namespace ReconstructHighlights {

fragment float CreateThresholdMap(
    texture2d<float> rgb [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    constexpr float Sat = 0.9999;
    constexpr float Thresh[] = { .99, 0.25, 0.25/2, 0.25/4 };
//    constexpr float Thresh[] = { 1, 0.5, 0.25, 0.125 };
    const float3 s = rgb.sample({filter::linear}, in.posUnit).rgb;
    const uint count = (uint)(s.r>Sat) + (uint)(s.g>Sat) + (uint)(s.b>Sat);
    return Thresh[count];
}

fragment float2 CreateHighlightMap(
    constant float3& scale [[buffer(0)]],
    constant float3& illum [[buffer(1)]],
    texture2d<float> rgbTxt [[texture(0)]],
    texture2d<float> threshTxt [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    // Calculate the magnitude of the current pixel and
    // determine whether it's a highlight
    const float MagMax = length(scale); // Maximum length of an RGB vector
    const float3 s = rgbTxt.sample({filter::linear}, in.posUnit).rgb;
    const float mag = length(scale*s) / MagMax; // Normalize magnitude so that the maximum brightness has mag=1
    const float thresh = threshTxt.sample({ filter::linear }, in.posUnit).r;
    if (mag < thresh) return 0;
    
    // Return the brightness of the illuminant using the sampled values
    const float3 k3 = s/illum;
    const float k = (k3.r+k3.g+k3.b)/3;
    return float2(k, 1);
}

fragment float2 Blur(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    constexpr float Strength = 2;
    const int2 pos = int2(in.pos.xy);
    const float coeff[] = {
        1 , 2 , 1 ,
        2 , 4 , 2 ,
        1 , 2 , 1 ,
    };
    
#define PX(x,y) Sample::RG(Sample::MirrorClamp, txt, pos+int2{x,y})
    const float2 s = PX(+0,+0);
    const float2 vals[] = {
        PX(-1,-1) , PX(+0,-1) , PX(+1,-1) ,
        PX(-1,+0) , s         , PX(+1,+0) ,
        PX(-1,+1) , PX(+0,+1) , PX(+1,+1) ,
    };
#undef PX
    
    // color = weighted average of neighbors' color, ignoring samples with alpha=0
    float color = 0;
    {
        float coeffSum = 0;
        for (size_t i=0; i<sizeof(coeff)/sizeof(*coeff); i++) {
            const float k = coeff[i];
            const float2 v = vals[i];
            // Ignore values with alpha=0
            // (alpha channel is the green channel for RG textures)
            if (v.g == 0) continue;
            color += k*v.r;
            coeffSum += k;
        }
        if (coeffSum > 0) {
            color /= coeffSum;
        }
    }
    
    // alpha = weighted average of neighbors' alpha, *not* ignoring samples with alpha=0
    float alpha = 0;
    {
        float coeffSum = 0;
        for (size_t i=0; i<sizeof(coeff)/sizeof(*coeff); i++) {
            const float k = coeff[i];
            const float2 v = vals[i];
            alpha += k*v.g;
            coeffSum += k;
        }
        if (coeffSum > 0) {
            alpha /= coeffSum;
            alpha = pow(alpha, Strength);
        }
    }
    return float2(color, alpha);
}

fragment float ReconstructHighlights(
    constant MDCTools::CFADesc& cfaDesc [[buffer(0)]],
    constant float3& illum [[buffer(1)]],
    texture2d<float> raw [[texture(0)]],
    texture2d<float> rgb [[texture(1)]],
    texture2d<float> map [[texture(2)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const MDCTools::CFAColor c = cfaDesc.color(pos);
    const float r = Sample::R(Sample::MirrorClamp, raw, pos);
    const float2 m = Sample::RG(Sample::MirrorClamp, map, pos);
    const float k = m.r; // Illuminant brightness
    const float α = m.g; // Alpha channel
    
    switch (c) {
    case MDCTools::CFAColor::Red:       return (α)*k*illum.r + (1-α)*r;
    case MDCTools::CFAColor::Green:     return (α)*k*illum.g + (1-α)*r;
    case MDCTools::CFAColor::Blue:      return (α)*k*illum.b + (1-α)*r;
    }
    return 0;
}

} // namespace ReconstructHighlights
} // namespace Shader
} // namespace ImagePipeline
} // namespace MDCTools
