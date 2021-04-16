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


static float V(float x) {
    if (x > 0) return x;
    return 0;
}

static uint C(float x) {
    if (x > 0) return 1;
    return 0;
}

static float avg(float a, float b) {
    const uint count = C(a)+C(b);
    if (!count) return 0;
    return (V(a)+V(b))/count;
}

static float avg(float a, float b, float c) {
    const uint count = C(a)+C(b)+C(c);
    if (!count) return 0;
    return (V(a)+V(b)+V(c))/count;
}

static float avg(float a, float b, float c, float d) {
    const uint count = C(a)+C(b)+C(c)+C(d);
    if (!count) return 0;
    return (V(a)+V(b)+V(c)+V(d))/count;
}

static float avg(float a, float b, float c, float d, float e) {
    const uint count = C(a)+C(b)+C(c)+C(d)+C(e);
    if (!count) return 0;
    return (V(a)+V(b)+V(c)+V(d)+V(e))/count;
}

static float sampleThresh(float thresh, texture2d<float> raw, int2 pos) {
    const float x = Sample::R(Sample::MirrorClamp, raw, pos);
    if (x < thresh) return x;
    return 0;
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




fragment float4 BlurHighlights(
    texture2d<float> rgb [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
#define PX(x,y) Sample::RGBA(Sample::MirrorClamp, rgb, pos+int2{x,y})
    const float4 s = PX(+0,+0);
    float4 vals[] = {
        PX(-1,-1), PX(+0,-1), PX(+1,-1),
        PX(-1,+0), s        , PX(+1,+0),
        PX(-1,+1), PX(+0,+1), PX(+1,+1)
    };
#undef PX
    
    float4 avg = 0;
    float4 count = 0;
    for (float4 x : vals) {
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
        
        if (x.a >= s.a) {
            avg.a += x.a;
            count.a += 1;
        }
    }
    
    avg /= count;
    return avg;
}

fragment float4 NormalizeByMagnitude(
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
    constexpr float Thresh = .99;
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



fragment float BlurR(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
#define PX(x,y) Sample::R(Sample::MirrorClamp, txt, pos+int2{x,y})
    return (
        1*PX(-1,-1) + 2*PX(+0,-1) + 1*PX(+1,-1) +
        2*PX(-1,+0) + 4*PX(+0,+0) + 2*PX(+1,+0) +
        1*PX(-1,+1) + 2*PX(+0,+1) + 1*PX(+1,+1) ) / 16;
#undef PX
}

fragment float4 BlurRGB(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
#define PX(x,y) Sample::RGB(Sample::MirrorClamp, txt, pos+int2{x,y})
    return float4((
        1*PX(-1,-1) + 2*PX(+0,-1) + 1*PX(+1,-1) +
        2*PX(-1,+0) + 4*PX(+0,+0) + 2*PX(+1,+0) +
        1*PX(-1,+1) + 2*PX(+0,+1) + 1*PX(+1,+1) ) / 16, 1);
#undef PX
}

//fragment float4 BlurRGBA(
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const int2 pos = int2(in.pos.xy);
//#define PX(x,y) Sample::RGBA(Sample::MirrorClamp, txt, pos+int2{x,y})
//    const float4 vals[] = {
//        (1./16)*PX(-1,-1) , (2./16)*PX(+0,-1) , (1./16)*PX(+1,-1) ,
//        (2./16)*PX(-1,+0) , (4./16)*PX(+0,+0) , (2./16)*PX(+1,+0) ,
//        (1./16)*PX(-1,+1) , (2./16)*PX(+0,+1) , (1./16)*PX(+1,+1) ,
//    };
//#undef PX
//    
//    float4 r = 0;
//    for (float4 v : vals) {
//        if (v.a == 0) continue;
//        r += v;
//    }
//    return r;
//}

fragment float4 BlurRGBA(
    constant float& strength [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
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
    
//    // Don't blur pixels that are fully opaque
//    if (s.a != 1) return s;
    
    float3 color = 0;
    // color = weighted average of neighbors' color, ignoring samples with alpha=0
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
            alpha = pow(alpha, 1-strength);
        }
    }
    return float4(color, alpha);
}

fragment float4 SourceOver(
    texture2d<float> src [[texture(0)]],
    texture2d<float> dst [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
//    return float4(1,1,1,0);
    const int2 pos = int2(in.pos.xy);
    const float4 a = Sample::RGBA(Sample::MirrorClamp, src, pos);
    const float4 b = Sample::RGBA(Sample::MirrorClamp, dst, pos);
    const float alpha = a.a+b.a*(1-a.a);
    const float3 color = (alpha>0 ? (a.rgb*a.a + b.rgb*b.a*(1-a.a))/alpha : 0);
    return float4(color, alpha);
}

fragment float4 BlurRGBIncrease(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float3 s = Sample::RGB(Sample::MirrorClamp, txt, pos);
#define PX(x,y) Sample::RGB(Sample::MirrorClamp, txt, pos+int2{x,y})
    float3 r = (
        1*PX(-1,-1) + 2*PX(+0,-1) + 1*PX(+1,-1) +
        2*PX(-1,+0) + 4*s         + 2*PX(+1,+0) +
        1*PX(-1,+1) + 2*PX(+0,+1) + 1*PX(+1,+1) ) / 16;
#undef PX
    r.r = max(r.r, s.r);
    r.g = max(r.g, s.g);
    r.b = max(r.b, s.b);
    return float4(r,1);
}

fragment float DiffHighlightMap(
    texture2d<float> map [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
#define PX(x,y) Sample::R(Sample::MirrorClamp, map, pos+int2{x,y})
    const float2 δ(
        // δx
        +1*PX(-1,-1) + +0*PX(+0,-1) + -1*PX(+1,-1) +
        +2*PX(-1,+0) + +0*PX(+0,+0) + -2*PX(+1,+0) +
        +1*PX(-1,+1) + +0*PX(+0,+1) + -1*PX(+1,+1) ,
        
        // δy
        +1*PX(-1,-1) + +2*PX(+0,-1) + +1*PX(+1,-1) +
        +0*PX(-1,+0) + +0*PX(+0,+0) + +0*PX(+1,+0) +
        -1*PX(-1,+1) + -2*PX(+0,+1) + -1*PX(+1,+1)
    );
#undef PX
    return length(δ);
}


fragment float Diff(
    texture2d<float> rgb [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
#define PX(x,y) Sample::RGB(Sample::MirrorClamp, rgb, pos+int2{x,y})
    const float3 δx(
        +1*PX(-1,-1) + +0*PX(+0,-1) + -1*PX(+1,-1) +
        +2*PX(-1,+0) + +0*PX(+0,+0) + -2*PX(+1,+0) +
        +1*PX(-1,+1) + +0*PX(+0,+1) + -1*PX(+1,+1)
    );
    
    const float3 δy(
        +1*PX(-1,-1) + +2*PX(+0,-1) + +1*PX(+1,-1) +
        +0*PX(-1,+0) + +0*PX(+0,+0) + +0*PX(+1,+0) +
        -1*PX(-1,+1) + -2*PX(+0,+1) + -1*PX(+1,+1)
    );
    
#undef PX
    const float2 δr(δx.r, δy.r);
    const float2 δg(δx.g, δy.g);
    const float2 δb(δx.b, δy.b);
    const float δavg = (length(δr)+length(δg)+length(δb)) / 3;
    return δavg;
}



fragment float BlurWithMask(
    texture2d<float> raw [[texture(0)]],
    texture2d<float> mask [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float r = Sample::R(Sample::MirrorClamp, raw, pos);
    const float m = Sample::R(Sample::MirrorClamp, mask, pos);
//    if (m == 0) return r;
    
#define PX(x,y) Sample::R(Sample::MirrorClamp, raw, pos+int2{x,y})
    return (
        1*PX(-1,-1) + 2*PX(+0,-1) + 1*PX(+1,-1) +
        2*PX(-1,+0) + 4*PX(+0,+0) + 2*PX(+1,+0) +
        1*PX(-1,+1) + 2*PX(+0,+1) + 1*PX(+1,+1) ) / 16;
#undef PX
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




// Most basic version
// Simply return illumant color, without scaling
//fragment float ReconstructHighlights(
//    constant CFADesc& cfaDesc [[buffer(0)]],
//    constant float3& illum [[buffer(1)]],
//    texture2d<float> raw [[texture(0)]],
//    texture2d<float> rgb [[texture(1)]],
//    VertexOutput in [[stage_in]]
//) {
//    constexpr float Thresh = 1;
//    const int2 pos = int2(in.pos.xy);
//    const CFAColor c = cfaDesc.color(pos);
//    const float s_raw = Sample::R(Sample::MirrorClamp, raw, pos);
//    const float2 off = float2(0,-.5)/float2(rgb.get_width(),rgb.get_height());
//    const float3 s_rgb = rgb.sample({filter::linear}, in.posUnit+off).rgb;
//    
//    if (s_rgb.r<Thresh && s_rgb.g<Thresh && s_rgb.b<Thresh) return s_raw;
////    if (s_raw < Thresh) return s_raw;
//    
//    switch (c) {
//    case CFAColor::Red:     return illum.r;
//    case CFAColor::Green:   return illum.g;
//    case CFAColor::Blue:    return illum.b;
//    }
//    return 0;
//}


//fragment float ReconstructHighlights(
//    constant CFADesc& cfaDesc [[buffer(0)]],
//    constant float3& illum [[buffer(1)]],
//    texture2d<float> raw [[texture(0)]],
//    texture2d<float> rgb [[texture(1)]],
//    texture2d<float> map [[texture(2)]],
//    VertexOutput in [[stage_in]]
//) {
//    const int2 pos = int2(in.pos.xy);
//    const CFAColor c = cfaDesc.color(pos);
//    const float r = Sample::R(Sample::MirrorClamp, raw, pos);
//    const float3 s = rgb.sample({filter::linear}, in.posUnit).rgb;
//    const float m = Sample::R(Sample::MirrorClamp, map, pos);
//    if (m == 0) return r;
//    
//    float savg = (s.r+s.g+s.b)/3;
//    
//    switch (c) {
//    case CFAColor::Red:     return (m*illum.r);
//    case CFAColor::Green:   return (m*illum.g);
//    case CFAColor::Blue:    return (m*illum.b);
//    }
//    
////    switch (c) {
////    case CFAColor::Red:     return (m*illum.r);
////    case CFAColor::Green:   return (m*illum.g);
////    case CFAColor::Blue:    return (m*illum.b);
////    }
//    
////    if (d > .8) return 0;
////    return d;
////    
////    return d;
////    
////    constexpr float DThresh = .95;
////    if (d >= DThresh) {
////        switch (c) {
////        case CFAColor::Red:     return (m*illum.r) + (1-m)*r;
////        case CFAColor::Green:   return (m*illum.g) + (1-m)*r;
////        case CFAColor::Blue:    return (m*illum.b) + (1-m)*r;
////        }
////    } else {
////        switch (c) {
////        case CFAColor::Red:     return m*illum.r;
////        case CFAColor::Green:   return m*illum.g;
////        case CFAColor::Blue:    return m*illum.b;
////        }
////    }
////    
////    switch (c) {
////    case CFAColor::Red:     return m2*illum.r+(1-m2)*r;
////    case CFAColor::Green:   return m2*illum.g+(1-m2)*r;
////    case CFAColor::Blue:    return m2*illum.b+(1-m2)*r;
////    }
//    
//    return 0;
//}




fragment float FixEdges(
    constant CFADesc& cfaDesc [[buffer(0)]],
    constant float3& illum [[buffer(1)]],
    texture2d<float> raw [[texture(0)]],
    texture2d<float> diff [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = cfaDesc.color(pos);
    const float r = Sample::R(Sample::MirrorClamp, raw, pos);
    const float δ = Sample::R(Sample::MirrorClamp, diff, pos);
    if (δ < .5) return r;
    switch (c) {
    case CFAColor::Red:     return illum.r;
    case CFAColor::Green:   return illum.g;
    case CFAColor::Blue:    return illum.b;
    }
//    return 0;
}



//fragment float ReconstructHighlights(
//    constant CFADesc& cfaDesc [[buffer(0)]],
//    constant float3& illum [[buffer(1)]],
//    texture2d<float> raw [[texture(0)]],
//    texture2d<float> map [[texture(1)]],
//    VertexOutput in [[stage_in]]
//) {
//    const int2 pos = int2(in.pos.xy);
//    const CFAColor c = cfaDesc.color(pos);
//    const float r = Sample::R(Sample::MirrorClamp, raw, pos);
//    const float m = Sample::R(Sample::MirrorClamp, map, pos);
//    if (m == 0) return r;
//    
//    switch (c) {
//    case CFAColor::Red:     return m*illum.r + (1-m)*r;
//    case CFAColor::Green:   return m*illum.g + (1-m)*r;
//    case CFAColor::Blue:    return m*illum.b + (1-m)*r;
//    }
//    
//    return 0;
//}










//fragment float ReconstructHighlights(
//    constant CFADesc& cfaDesc [[buffer(0)]],
//    constant float3& illum [[buffer(1)]],
//    texture2d<float> raw [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    constexpr float Thresh = 1;
//    const int2 pos = int2(in.pos.xy);
//    const CFAColor c = cfaDesc.color(pos);
//    const CFAColor cn = cfaDesc.color(pos.x+1, pos.y);
//    const float s  = sampleThresh(Thresh, raw, pos+int2{+0,+0});
//    const float u  = sampleThresh(Thresh, raw, pos+int2{+0,-1});
//    const float d  = sampleThresh(Thresh, raw, pos+int2{+0,+1});
//    const float l  = sampleThresh(Thresh, raw, pos+int2{-1,+0});
//    const float r  = sampleThresh(Thresh, raw, pos+int2{+1,+0});
//    const float ul = sampleThresh(Thresh, raw, pos+int2{-1,-1});
//    const float ur = sampleThresh(Thresh, raw, pos+int2{+1,-1});
//    const float dl = sampleThresh(Thresh, raw, pos+int2{-1,+1});
//    const float dr = sampleThresh(Thresh, raw, pos+int2{+1,+1});
////    if (s > 0) return s;
//    // If no pixel in the 3x3 neighborhood is saturated, then return the pixel
//    if (s>0 && u>0 && d>0 && l>0 && r>0 && ul>0 && ur>0 && dl>0 && dr>0) return s;
//    
//    float r̄ = 0;
//    float ḡ = 0;
//    float b̄ = 0;
//    if (c == CFAColor::Red) {
//        r̄ = s;
//        ḡ = avg(u,d,l,r);
//        b̄ = avg(ul,ur,dl,dr);
//    } else if (c==CFAColor::Green && cn==CFAColor::Red) {
//        r̄ = avg(l,r);
//        ḡ = avg(s,ul,ur,dl,dr);
//        b̄ = avg(u,d);
//    } else if (c==CFAColor::Green && cn==CFAColor::Blue) {
//        r̄ = avg(u,d);
//        ḡ = avg(s,ul,ur,dl,dr);
//        b̄ = avg(l,r);
//    } else if (c == CFAColor::Blue) {
//        ḡ = avg(u,d,l,r);
//        r̄ = avg(ul,ur,dl,dr);
//        b̄ = s;
//    }
//    
//    const float kr = (r̄>0 ? r̄/illum.r : 0);
//    const float kg = (ḡ>0 ? ḡ/illum.g : 0);
//    const float kb = (b̄>0 ? b̄/illum.b : 0);
//    float k = avg(kr, kg, kb);
////    // If the scale factor tries to reduce the , don't touch the pixel
////    if (k < 1) {
////        return s;
////    }
//    
//    if (k == 0) {
//        k = 1;
//    }
//    
//    const float3 i = k*illum;
//    
////    // This scoped bit works well to prevent HR from being applied to the orange highlight,
////    // by preventing short-circuiting if any of the scaled illuminant channels are less than
////    // the average sampled channel. Ie -- only allow the correction to increase the the pixel value.
////    {
////        const float s  = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+0});
////        const float u  = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,-1});
////        const float d  = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+1});
////        const float l  = Sample::R(Sample::MirrorClamp, raw, pos+int2{-1,+0});
////        const float r  = Sample::R(Sample::MirrorClamp, raw, pos+int2{+1,+0});
////        const float ul = Sample::R(Sample::MirrorClamp, raw, pos+int2{-1,-1});
////        const float ur = Sample::R(Sample::MirrorClamp, raw, pos+int2{+1,-1});
////        const float dl = Sample::R(Sample::MirrorClamp, raw, pos+int2{-1,+1});
////        const float dr = Sample::R(Sample::MirrorClamp, raw, pos+int2{+1,+1});
////        
////        float r̄ = 0;
////        float ḡ = 0;
////        float b̄ = 0;
////        if (c == CFAColor::Red) {
////            r̄ = s;
////            ḡ = avg(u,d,l,r);
////            b̄ = avg(ul,ur,dl,dr);
////        } else if (c==CFAColor::Green && cn==CFAColor::Red) {
////            r̄ = avg(l,r);
////            ḡ = avg(s,ul,ur,dl,dr);
////            b̄ = avg(u,d);
////        } else if (c==CFAColor::Green && cn==CFAColor::Blue) {
////            r̄ = avg(u,d);
////            ḡ = avg(s,ul,ur,dl,dr);
////            b̄ = avg(l,r);
////        } else if (c == CFAColor::Blue) {
////            ḡ = avg(u,d,l,r);
////            r̄ = avg(ul,ur,dl,dr);
////            b̄ = s;
////        }
////        
////        const float Factor = 1;
////        if (i.r<Factor*r̄ || i.g<Factor*ḡ || i.b<Factor*b̄) {
////            return s;
////        }
////    }
//    
//    if (c == CFAColor::Red) {
//        return i.r;
//    } else if (c==CFAColor::Green) {
//        return i.g;
//    } else if (c == CFAColor::Blue) {
//        return i.b;
//    }
//    return 0;
//}








//fragment float ReconstructHighlights(
//    constant CFADesc& cfaDesc [[buffer(0)]],
//    constant float3& illum [[buffer(1)]],
//    texture2d<float> raw [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    constexpr float Thresh = 1;
//    const int2 pos = int2(in.pos.xy);
//    const CFAColor c = cfaDesc.color(pos);
//    const CFAColor cn = cfaDesc.color(pos.x+1, pos.y);
//    const float s  = sampleThresh(Thresh, raw, pos+int2{+0,+0});
//    const float u  = sampleThresh(Thresh, raw, pos+int2{+0,-1});
//    const float d  = sampleThresh(Thresh, raw, pos+int2{+0,+1});
//    const float l  = sampleThresh(Thresh, raw, pos+int2{-1,+0});
//    const float r  = sampleThresh(Thresh, raw, pos+int2{+1,+0});
//    const float ul = sampleThresh(Thresh, raw, pos+int2{-1,-1});
//    const float ur = sampleThresh(Thresh, raw, pos+int2{+1,-1});
//    const float dl = sampleThresh(Thresh, raw, pos+int2{-1,+1});
//    const float dr = sampleThresh(Thresh, raw, pos+int2{+1,+1});
//    if (s>0) return s;
////    if (s>0 && u>0 && d>0 && l>0 && r>0) return s;
////    if (s>0 && u>0 && d>0 && l>0 && r>0 && ul>0 && ur>0 && dl>0 && dr>0) return s;
//    
//    switch (c) {
//    case CFAColor::Red:     return illum.r;
//    case CFAColor::Green:   return illum.g;
//    case CFAColor::Blue:    return illum.b;
//    }
//}



//fragment float ReconstructHighlights(
//    constant CFADesc& cfaDesc [[buffer(0)]],
//    constant float3& illum [[buffer(1)]],
//    texture2d<float> raw [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    constexpr float Thresh = 1;
//    const int2 pos = int2(in.pos.xy);
//    const CFAColor c = cfaDesc.color(pos);
//    const CFAColor cn = cfaDesc.color(pos.x+1, pos.y);
//    const float s  = sampleThresh(Thresh, raw, pos+int2{+0,+0});
//    const float u  = sampleThresh(Thresh, raw, pos+int2{+0,-1});
//    const float d  = sampleThresh(Thresh, raw, pos+int2{+0,+1});
//    const float l  = sampleThresh(Thresh, raw, pos+int2{-1,+0});
//    const float r  = sampleThresh(Thresh, raw, pos+int2{+1,+0});
//    const float ul = sampleThresh(Thresh, raw, pos+int2{-1,-1});
//    const float ur = sampleThresh(Thresh, raw, pos+int2{+1,-1});
//    const float dl = sampleThresh(Thresh, raw, pos+int2{-1,+1});
//    const float dr = sampleThresh(Thresh, raw, pos+int2{+1,+1});
//    if (s > 0) return s;
////    if (s>0 && u>0 && d>0 && l>0 && r>0 && ul>0 && ur>0 && dl>0 && dr>0) return s;
//    
//    float r̄ = 0;
//    float ḡ = 0;
//    float b̄ = 0;
//    if (c == CFAColor::Red) {
//        ḡ = avg(u,d,l,r);
//        b̄ = avg(ul,ur,dl,dr);
//    } else if (c==CFAColor::Green && cn==CFAColor::Red) {
//        r̄ = avg(l,r);
//        ḡ = avg(ul,ur,dl,dr);
//        b̄ = avg(u,d);
//    } else if (c==CFAColor::Green && cn==CFAColor::Blue) {
//        r̄ = avg(u,d);
//        ḡ = avg(ul,ur,dl,dr);
//        b̄ = avg(l,r);
//    } else if (c == CFAColor::Blue) {
//        ḡ = avg(u,d,l,r);
//        r̄ = avg(ul,ur,dl,dr);
//    }
//    
//    const float kr = (r̄>0 ? r̄/illum.r : 0);
//    const float kg = (ḡ>0 ? ḡ/illum.g : 0);
//    const float kb = (b̄>0 ? b̄/illum.b : 0);
//    float k = avg(kr, kg, kb);
//    if (k == 0) {
//        k = 1;
//    }
//    
//    if (c == CFAColor::Red) {
//        return k*illum.r;
//    } else if (c==CFAColor::Green) {
//        return k*illum.g;
//    } else if (c == CFAColor::Blue) {
//        return k*illum.b;
//    }
//    return 0;
//}


//// Decent, but makes highlights blocky
//fragment float ReconstructHighlights2(
//    constant CFADesc& cfaDesc [[buffer(0)]],
//    constant float3& illum [[buffer(1)]],
//    texture2d<float> raw [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const float Thresh = 1;
//    const int2 pos = int2(in.pos.xy);
//    const CFAColor c = cfaDesc.color(pos);
//    const float s = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+0});
//    const float ᐊ = Sample::R(Sample::MirrorClamp, raw, pos+int2{-1,+0});
//    const float ᐅ = Sample::R(Sample::MirrorClamp, raw, pos+int2{+1,+0});
//    const float ᐃ = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,-1});
//    const float ᐁ = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+1});
//    if (s>=Thresh || ᐊ>=Thresh || ᐅ>=Thresh || ᐃ>=Thresh || ᐁ>=Thresh) {
//        switch (c) {
//        case CFAColor::Red:     return illum.r;
//        case CFAColor::Green:   return illum.g;
//        case CFAColor::Blue:    return illum.b;
//        }
//    }
//    return s;
//}

















//fragment float ReconstructHighlights(
//    constant CFADesc& cfaDesc [[buffer(0)]],
//    constant float3& illum [[buffer(1)]],
//    texture2d<float> raw [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const float Thresh = 1;
//    const int2 pos = int2(in.pos.xy);
//    const CFAColor c = cfaDesc.color(pos);
//    const CFAColor cn = cfaDesc.color(pos.x+1, pos.y);
//    const float s = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+0});
//    if (s < Thresh) return s;
//    
//    
//    
//    const float ᐊ = Sample::R(Sample::MirrorClamp, raw, pos+int2{-1,+0});
//    const float ᐅ = Sample::R(Sample::MirrorClamp, raw, pos+int2{+1,+0});
//    const float ᐃ = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,-1});
//    const float ᐁ = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+1});
//    const float sumᐊᐅ = (ᐊ<Thresh ? ᐊ : 0) + (ᐅ<Thresh ? ᐅ : 0);
//    const float sumᐃᐁ = (ᐃ<Thresh ? ᐃ : 0) + (ᐁ<Thresh ? ᐁ : 0);
//    const uint countᐊᐅ = (ᐊ<Thresh ? 1 : 0) + (ᐅ<Thresh ? 1 : 0);
//    const uint countᐃᐁ = (ᐃ<Thresh ? 1 : 0) + (ᐁ<Thresh ? 1 : 0);
////    const uint avgᐊᐅ = 0;
////    const uint nᐃᐁcount = (u<Thresh ? 1 : 0) + (d<Thresh ? 1 : 0);
////    uint ᐃᐁᐊᐅ;
//    if (c == CFAColor::Red) {
//        return illum.r;
//        // Use neighboring greens to determine our color
//        const uint gcount = countᐊᐅ+countᐃᐁ;
//        const float ḡ = (sumᐊᐅ+sumᐃᐁ)/max((uint)1,gcount);
//        if (gcount) {
//            return ḡ * (illum.r / illum.g);
//        } else {
////            return 0;
//            return illum.r;
//        }
//    
//    } else if (c==CFAColor::Green && cn==CFAColor::Red) {
//        return illum.g;
//        const float Σr = sumᐊᐅ;
//        const float Σb = sumᐃᐁ;
//        const uint rcount = countᐊᐅ;
//        const uint bcount = countᐃᐁ;
//        const float r̄ = Σr/max((uint)1,rcount);
//        const float b̄ = Σb/max((uint)1,bcount);
//        const float gr̄ = r̄ * (illum.g / illum.r); // Green according to the average red channel
//        const float gb̄ = b̄ * (illum.g / illum.b); // Green according to the average blue channel
//        if (rcount && bcount) {
//            return (gr̄+gb̄)/2;   // Neighbor red and blue channels have valid values
//        } else if (rcount) {
//            return gr̄;          // Neighbor red channel has non-saturated values
//        } else if (bcount) {
//            return gb̄;          // Neighbor blue channel has non-saturated values
//        } else {
//            return illum.g;     // No neighbors have non-saturated values (just return illuminant color)
//        }
//    
//    } else if (c==CFAColor::Green && cn==CFAColor::Blue) {
//        return illum.g;
//        const float Σr = sumᐃᐁ;
//        const float Σb = sumᐊᐅ;
//        const uint rcount = countᐃᐁ;
//        const uint bcount = countᐊᐅ;
//        const float r̄ = Σr/max((uint)1,rcount);
//        const float b̄ = Σb/max((uint)1,bcount);
//        const float gr̄ = r̄ * (illum.g / illum.r); // Green according to the average red channel
//        const float gb̄ = b̄ * (illum.g / illum.b); // Green according to the average blue channel
//        if (rcount && bcount) {
//            return (gr̄+gb̄)/2;   // Neighbor red and blue channels have valid values
//        } else if (rcount) {
//            return gr̄;          // Neighbor red channel has non-saturated values
//        } else if (bcount) {
//            return gb̄;          // Neighbor blue channel has non-saturated values
//        } else {
//            return illum.g;     // No neighbors have non-saturated values (just return illuminant color)
//        }
//    
//    } else if (c == CFAColor::Blue) {
//        return illum.b;
//        // Use neighboring greens to determine our color
//        const uint gcount = countᐊᐅ+countᐃᐁ;
//        const float ḡ = (sumᐊᐅ+sumᐃᐁ)/max((uint)1,gcount);
//        if (gcount) {
//            return ḡ * (illum.b / illum.g);
//        } else {
//            return illum.b;
//        }
//    }
//    
//    return 0;
//}

// *** This works decently, but it still makes the edges of some highlights look
// *** too harsh, especially on the oranges in indoor_night2_53
//fragment float ReconstructHighlights(
//    constant CFADesc& cfaDesc [[buffer(0)]],
//    constant float3& badPixelFactors [[buffer(1)]],
//    constant float3& goodPixelFactors [[buffer(2)]],
//    texture2d<float> raw [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const float Thresh = 1;
//    const int2 pos = int2(in.pos.xy);
//    const CFAColor c = cfaDesc.color(pos);
//    const float s = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+0});
//    const float l = Sample::R(Sample::MirrorClamp, raw, pos+int2{-1,+0});
//    const float r = Sample::R(Sample::MirrorClamp, raw, pos+int2{+1,+0});
//    const float u = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,-1});
//    const float d = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+1});
//    
//    // If any of the surrounding pixels are saturated...
//    if (s>=Thresh || l>=Thresh || r>=Thresh || u>=Thresh || d>=Thresh) {
//        switch (c) {
//        case CFAColor::Red:     return badPixelFactors.r;
//        case CFAColor::Green:   return badPixelFactors.g;
//        case CFAColor::Blue:    return badPixelFactors.b;
//        }
//    }
//    
//    return s;
//    
//    
////    // Pass-through if this pixel isn't saturated
////    if (s < Thresh) return s;
////    return 0;
////    
////    // If all of the surrounding pixels are saturated...
//////    if (l>=Thresh && r>=Thresh && u>=Thresh && d>=Thresh) {
////        switch (c) {
////        case CFAColor::Red:     return badPixelFactors.r*s;
////        case CFAColor::Green:   return badPixelFactors.g*s;
////        case CFAColor::Blue:    return badPixelFactors.b*s;
////        }
//////    }
////    
////    // There's at least one valid pixel in our neighborhood...
////    const float x̄ = (l+r+u+d)/4;
////    switch (c) {
////    case CFAColor::Red:     return goodPixelFactors.r*x̄;
////    case CFAColor::Green:   return goodPixelFactors.g*x̄;
////    case CFAColor::Blue:    return goodPixelFactors.b*x̄;
////    }
//}



//fragment float ReconstructHighlights(
//    constant CFADesc& cfaDesc [[buffer(0)]],
//    constant float3& badPixelFactors [[buffer(1)]],
//    constant float3& goodPixelFactors [[buffer(2)]],
//    texture2d<float> raw [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const float Thresh = 1;
//    const int2 pos = int2(in.pos.xy);
//    const CFAColor c = cfaDesc.color(pos);
//    const float s = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+0});
//    const float l = Sample::R(Sample::MirrorClamp, raw, pos+int2{-1,+0});
//    const float r = Sample::R(Sample::MirrorClamp, raw, pos+int2{+1,+0});
//    const float u = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,-1});
//    const float d = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+1});
//    
//    // Pass-through if this pixel isn't saturated
//    if (s < Thresh) return s;
//    
//    // If all of the surrounding pixels are saturated...
//    if (l>=Thresh && r>=Thresh && u>=Thresh && d>=Thresh) {
//        switch (c) {
//        case CFAColor::Red:     return badPixelFactors.r*s;
//        case CFAColor::Green:   return badPixelFactors.g*s;
//        case CFAColor::Blue:    return badPixelFactors.b*s;
//        }
//    }
//    
//    // There's at least one valid pixel in our neighborhood...
//    const float x̄ = (l+r+u+d)/4;
//    switch (c) {
//    case CFAColor::Red:     return goodPixelFactors.r*x̄;
//    case CFAColor::Green:   return goodPixelFactors.g*x̄;
//    case CFAColor::Blue:    return goodPixelFactors.b*x̄;
//    }
//}

} // namespace ImagePipeline
} // namespace Shader
} // namespace CFAViewer
