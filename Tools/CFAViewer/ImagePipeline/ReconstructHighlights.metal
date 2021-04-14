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
    const float x = Sample::R(Sample::MirrorClamp, raw,  pos);
    if (x < thresh) return x;
    return 0;
}

fragment float ReconstructHighlights(
    constant CFADesc& cfaDesc [[buffer(0)]],
    constant float3& illum [[buffer(1)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    constexpr float Thresh = 1;
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = cfaDesc.color(pos);
    const CFAColor cn = cfaDesc.color(pos.x+1, pos.y);
    const float s  = sampleThresh(Thresh, raw, pos+int2{+0,+0});
    const float u  = sampleThresh(Thresh, raw, pos+int2{+0,-1});
    const float d  = sampleThresh(Thresh, raw, pos+int2{+0,+1});
    const float l  = sampleThresh(Thresh, raw, pos+int2{-1,+0});
    const float r  = sampleThresh(Thresh, raw, pos+int2{+1,+0});
    const float ul = sampleThresh(Thresh, raw, pos+int2{-1,-1});
    const float ur = sampleThresh(Thresh, raw, pos+int2{+1,-1});
    const float dl = sampleThresh(Thresh, raw, pos+int2{-1,+1});
    const float dr = sampleThresh(Thresh, raw, pos+int2{+1,+1});
//    if (s > 0) return s;
    // If no pixel in the 3x3 neighborhood is saturated, then return the pixel
    if (s>0 && u>0 && d>0 && l>0 && r>0 && ul>0 && ur>0 && dl>0 && dr>0) return s;
    
    float r̄ = 0;
    float ḡ = 0;
    float b̄ = 0;
    if (c == CFAColor::Red) {
        r̄ = s;
        ḡ = avg(u,d,l,r);
        b̄ = avg(ul,ur,dl,dr);
    } else if (c==CFAColor::Green && cn==CFAColor::Red) {
        r̄ = avg(l,r);
        ḡ = avg(s,ul,ur,dl,dr);
        b̄ = avg(u,d);
    } else if (c==CFAColor::Green && cn==CFAColor::Blue) {
        r̄ = avg(u,d);
        ḡ = avg(s,ul,ur,dl,dr);
        b̄ = avg(l,r);
    } else if (c == CFAColor::Blue) {
        ḡ = avg(u,d,l,r);
        r̄ = avg(ul,ur,dl,dr);
        b̄ = s;
    }
    
    const float kr = (r̄>0 ? r̄/illum.r : 0);
    const float kg = (ḡ>0 ? ḡ/illum.g : 0);
    const float kb = (b̄>0 ? b̄/illum.b : 0);
    float k = avg(kr, kg, kb);
//    // If the scale factor tries to reduce the , don't touch the pixel
//    if (k < 1) {
//        return s;
//    }
    
    if (k == 0) {
        k = 1;
    }
    
    const float3 i = k*illum;
    
//    // This scoped bit works well to prevent HR from being applied to the orange highlight,
//    // by preventing short-circuiting if any of the scaled illuminant channels are less than
//    // the average sampled channel. Ie -- only allow the correction to increase the the pixel value.
//    {
//        const float s  = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+0});
//        const float u  = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,-1});
//        const float d  = Sample::R(Sample::MirrorClamp, raw, pos+int2{+0,+1});
//        const float l  = Sample::R(Sample::MirrorClamp, raw, pos+int2{-1,+0});
//        const float r  = Sample::R(Sample::MirrorClamp, raw, pos+int2{+1,+0});
//        const float ul = Sample::R(Sample::MirrorClamp, raw, pos+int2{-1,-1});
//        const float ur = Sample::R(Sample::MirrorClamp, raw, pos+int2{+1,-1});
//        const float dl = Sample::R(Sample::MirrorClamp, raw, pos+int2{-1,+1});
//        const float dr = Sample::R(Sample::MirrorClamp, raw, pos+int2{+1,+1});
//        
//        float r̄ = 0;
//        float ḡ = 0;
//        float b̄ = 0;
//        if (c == CFAColor::Red) {
//            r̄ = s;
//            ḡ = avg(u,d,l,r);
//            b̄ = avg(ul,ur,dl,dr);
//        } else if (c==CFAColor::Green && cn==CFAColor::Red) {
//            r̄ = avg(l,r);
//            ḡ = avg(s,ul,ur,dl,dr);
//            b̄ = avg(u,d);
//        } else if (c==CFAColor::Green && cn==CFAColor::Blue) {
//            r̄ = avg(u,d);
//            ḡ = avg(s,ul,ur,dl,dr);
//            b̄ = avg(l,r);
//        } else if (c == CFAColor::Blue) {
//            ḡ = avg(u,d,l,r);
//            r̄ = avg(ul,ur,dl,dr);
//            b̄ = s;
//        }
//        
//        const float Factor = 1;
//        if (i.r<Factor*r̄ || i.g<Factor*ḡ || i.b<Factor*b̄) {
//            return s;
//        }
//    }
    
    if (c == CFAColor::Red) {
        return i.r;
    } else if (c==CFAColor::Green) {
        return i.g;
    } else if (c == CFAColor::Blue) {
        return i.b;
    }
    return 0;
}








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
