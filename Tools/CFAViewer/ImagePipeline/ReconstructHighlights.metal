#import <metal_stdlib>
#import "MetalUtil.h"
#import "ImagePipelineTypes.h"
using namespace metal;
using namespace CFAViewer::MetalUtil;
using namespace CFAViewer::MetalUtil::Standard;
using namespace CFAViewer::ImagePipeline;

namespace CFAViewer {
namespace Shader {
namespace ReconstructHighlights {

fragment float4 DebayerDownsample(
    constant CFADesc& cfaDesc [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos(2*(int)in.pos.x, 2*in.pos.y);
    const CFAColor c = cfaDesc.color(pos+int2{0,0});
    const CFAColor cn = cfaDesc.color(pos+int2{1,0});
    const float s00 = Sample::R(Sample::MirrorClamp, raw, pos+int2{0,0});
    const float s01 = Sample::R(Sample::MirrorClamp, raw, pos+int2{0,1});
    const float s10 = Sample::R(Sample::MirrorClamp, raw, pos+int2{1,0});
    const float s11 = Sample::R(Sample::MirrorClamp, raw, pos+int2{1,1});
    
    if (c == CFAColor::Red) {
        return float4(s00,(s01+s10)/2,s11,1);
    } else if (c==CFAColor::Green && cn==CFAColor::Red) {
        return float4(s10,(s00+s11)/2,s01,1);
    } else if (c==CFAColor::Green && cn==CFAColor::Blue) {
        return float4(s01,(s00+s11)/2,s10,1);
    } else if (c == CFAColor::Blue) {
        return float4(s11,(s01+s10)/2,s00,1);
    }
    return 0;
}

fragment float4 Normalize(
    texture2d<float> rgb [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float MagMax = length(float3(1,1,1)); // Maximum length of an RGB vector
    const int2 pos = int2(in.pos.xy);
    const float3 s = Sample::RGB(Sample::MirrorClamp, rgb, pos);
    const float mag = length(s) / MagMax; // Normalize magnitude so that the maximum brightness has mag=1
    return float4(s*mag, 1);
}

fragment float4 ExpandHighlights(
    texture2d<float> rgb [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
#define PX(x,y) Sample::RGB(Sample::MirrorClamp, rgb, pos+int2{x,y})
    const float3 s = PX(+0,+0);
    float3 vals[] = {
        PX(-1,-1), PX(+0,-1), PX(+1,-1),
        PX(-1,+0), s        , PX(+1,+0),
        PX(-1,+1), PX(+0,+1), PX(+1,+1)
    };
#undef PX
    
    float3 avg = 0;
    float3 count = 0;
    for (float3 x : vals) {
        if (x.r >= s.r) {
            avg.r += x.r;
            count.r += 1;
        }
        
        if (x.g >= s.g) {
            avg.g += x.g;
            count.g += 1;
        }
        
        if (x.b >= s.b) {
            avg.b += x.b;
            count.b += 1;
        }
    }
    
    avg /= count;
    return float4(avg, 1);
}

fragment float4 CreateHighlightMap(
    constant float3& illum [[buffer(0)]],
    texture2d<float> rgb [[texture(0)]],
    texture2d<float> rgbLight [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    constexpr float Thresh = .85;
    const float2 off = float2(0,-.5)/float2(rgb.get_width(),rgb.get_height());
    {
        const float3 s_rgbLight = rgbLight.sample({filter::linear}, in.posUnit+off).rgb;
        if (s_rgbLight.r<Thresh && s_rgbLight.g<Thresh && s_rgbLight.b<Thresh) return float4(1,0,0,0);
    }
    
    const float3 s_rgb = rgb.sample({filter::linear}, in.posUnit+off).rgb;
    const float3 k3 = s_rgb/illum;
    const float k = (k3.r+k3.g+k3.b)/3;
    return float4(k*illum, 1);
}

fragment float4 Blur(
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
    
#define PX(x,y) Sample::RGBA(Sample::MirrorClamp, txt, pos+int2{x,y})
    const float4 s = PX(+0,+0);
    const float4 vals[] = {
        PX(-1,-1) , PX(+0,-1) , PX(+1,-1) ,
        PX(-1,+0) , s         , PX(+1,+0) ,
        PX(-1,+1) , PX(+0,+1) , PX(+1,+1) ,
    };
#undef PX
    
    // color = weighted average of neighbors' color, ignoring samples with alpha=0
    float3 color = 0;
    {
        float coeffSum = 0;
        for (size_t i=0; i<sizeof(coeff)/sizeof(*coeff); i++) {
            const float k = coeff[i];
            const float4 v = vals[i];
            if (v.a == 0) continue;
            color += k*v.rgb;
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
            const float4 v = vals[i];
            alpha += k*v.a;
            coeffSum += k;
        }
        if (coeffSum > 0) {
            alpha /= coeffSum;
            alpha = pow(alpha, Strength);
        }
    }
    return float4(color, alpha);
}

fragment float ReconstructHighlights(
    constant CFADesc& cfaDesc [[buffer(0)]],
    constant float3& illum [[buffer(1)]],
    texture2d<float> raw [[texture(0)]],
    texture2d<float> rgb [[texture(1)]],
    texture2d<float> map [[texture(2)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = cfaDesc.color(pos);
    const float r = Sample::R(Sample::MirrorClamp, raw, pos);
    const float4 m = Sample::RGBA(Sample::MirrorClamp, map, pos);
    
    switch (c) {
    case CFAColor::Red:     return m.a*m.r + (1-m.a)*r;
    case CFAColor::Green:   return m.a*m.g + (1-m.a)*r;
    case CFAColor::Blue:    return m.a*m.b + (1-m.a)*r;
    }
    return 0;
}

} // namespace ReconstructHighlights
} // namespace Shader
} // namespace CFAViewer
