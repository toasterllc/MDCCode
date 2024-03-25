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
namespace DebayerLMMSE {

float SRGBGammaForward(float x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.0031308) return 12.92*x;
    return 1.055*pow(x, 1/2.4)-.055;
}

float SRGBGammaReverse(float x) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    if (x <= 0.04045) return x/12.92;
    return pow((x+.055)/1.055, 2.4);
}

fragment float GammaForward(
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    return SRGBGammaForward(Sample::R(raw, int2(in.pos.xy)));
}

fragment float4 GammaReverse(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = Sample::RGB(txt, int2(in.pos.xy));
    return float4(SRGBGammaReverse(c.r), SRGBGammaReverse(c.g), SRGBGammaReverse(c.b), 1);
}

fragment float Interp5(
    constant bool& h [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    return  -.25*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?-2:+0,!h?-2:+0})   +
            +0.5*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?-1:+0,!h?-1:+0})   +
            +0.5*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?+0:+0,!h?+0:+0})   +
            +0.5*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?+1:+0,!h?+1:+0})   +
            -.25*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?+2:+0,!h?+2:+0})   ;
}

fragment float NoiseEst(
    constant CFADesc& cfaDesc [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    texture2d<float> filtered [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = cfaDesc.color(pos);
    const float r = Sample::R(raw, pos);
    const float f = Sample::R(filtered, pos);
    if (c == CFAColor::Green) return r-f;
    else                      return f-r;
}

// This is just 2 passes of NoiseEst combined into 1
// TODO: profile this again. remember though that the -nextDrawable/-waitUntilCompleted pattern will cause our minimum render time to be the display refresh rate (16ms). so instead, for each iteration, we should only count the time _after_ -nextDrawable completes to the time after -waitUntilCompleted completes
//fragment void NoiseEst2(
//    texture2d<float> raw [[texture(0)]],
//    texture2d<float> filteredH [[texture(1)]],
//    texture2d<float> filteredV [[texture(2)]],
//    texture2d<float, access::read_write> diffH [[texture(3)]],
//    texture2d<float, access::read_write> diffV [[texture(4)]],
//    VertexOutput in [[stage_in]]
//) {
//    const int2 pos = int2(in.pos.xy);
//    const sampler s;
//    const bool green = ((!(pos.y%2) && !(pos.x%2)) || ((pos.y%2) && (pos.x%2)));
//    const float r = Sample::R(raw, pos);
//    const float filteredH = Sample::R(filteredH, pos);
//    const float filteredV = Sample::R(filteredV, pos);
//    
//    if (green) {
//        diffH.write(float4(raw-filteredH), pos);
//        diffV.write(float4(raw-filteredV), pos);
//    } else {
//        diffH.write(float4(filteredH-raw), pos);
//        diffV.write(float4(filteredV-raw), pos);
//    }
//}

fragment float Smooth9(
    constant bool& h [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    return  0.0312500*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?-4:+0,!h?-4:+0})     +
            0.0703125*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?-3:+0,!h?-3:+0})     +
            0.1171875*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?-2:+0,!h?-2:+0})     +
            0.1796875*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?-1:+0,!h?-1:+0})     +
            0.2031250*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?+0:+0,!h?+0:+0})     +
            0.1796875*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?+1:+0,!h?+1:+0})     +
            0.1171875*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?+2:+0,!h?+2:+0})     +
            0.0703125*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?+3:+0,!h?+3:+0})     +
            0.0312500*Sample::R(Sample::MirrorClamp, raw, pos+int2{h?+4:+0,!h?+4:+0})     ;
}

constant bool UseZhangCodeEst = false;

fragment float4 CalcG(
    constant CFADesc& cfaDesc [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    texture2d<float> filteredH [[texture(1)]],
    texture2d<float> diffH [[texture(2)]],
    texture2d<float> filteredV [[texture(3)]],
    texture2d<float> diffV [[texture(4)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = cfaDesc.color(pos);
    const float r = Sample::R(raw, pos);
    float g = 0;
    if (c==CFAColor::Red || c==CFAColor::Blue) {
        const int M = 4;
        const float DivEpsilon = 0.1/(255*255);
        
        // Adjust loop indices m = -M,...,M when necessary to
        // compensate for left and right boundaries.  We effectively
        // do zero-padded boundary handling.
        int m0 = (pos.x>=M ? -M : -pos.x);
        int m1 = (pos.x<(int)raw.get_width()-M ? M : (int)raw.get_width()-pos.x-1);
        
        // The following computes
        // ph =   var   FilteredH[i + m]
        //      m=-M,...,M
        // Rh =   mean  (FilteredH[i + m] - DiffH[i + m])^2
        //      m=-M,...,M
        // h = LMMSE estimate
        // H = LMMSE estimate accuracy (estimated variance of h)
        float mom1 = 0;
        float ph = 0;
        float Rh = 0;
        for (int m=m0; m <= m1; m++) {
            float Temp = 0;
            Temp = Sample::R(Sample::MirrorClamp, filteredH, pos+int2{m,0});
            mom1 += Temp;
            ph += Temp*Temp;
            Temp -= Sample::R(Sample::MirrorClamp, diffH, pos+int2{m,0});
            Rh += Temp*Temp;
        }
        
        float mh = 0;
        // Compute mh = mean_m FilteredH[i + m]
        if (!UseZhangCodeEst) mh = mom1/(2*M + 1);
        // Compute mh as in Zhang's MATLAB code
        else mh = Sample::R(filteredH, pos);
        
        ph = ph/(2*M) - mom1*mom1/(2*M*(2*M + 1));
        Rh = Rh/(2*M + 1) + DivEpsilon;
        float h = mh + (ph/(ph + Rh))*(Sample::R(diffH,pos)-mh);
        float H = ph - (ph/(ph + Rh))*ph + DivEpsilon;
        
        // Adjust loop indices for top and bottom boundaries
        m0 = (pos.y>=M ? -M : -pos.y);
        m1 = (pos.y<(int)raw.get_height()-M ? M : (int)raw.get_height()-pos.y-1);
        
        // The following computes
        // pv =   var   FilteredV[i + m]
        //      m=-M,...,M
        // Rv =   mean  (FilteredV[i + m] - DiffV[i + m])^2
        //      m=-M,...,M
        // v = LMMSE estimate
        // V = LMMSE estimate accuracy (estimated variance of v)
        mom1 = 0;
        float pv = 0;
        float Rv = 0;
        for (int m=m0; m<=m1; m++) {
            float Temp = 0;
            Temp = Sample::R(Sample::MirrorClamp, filteredV, pos+int2{0,m});
            mom1 += Temp;
            pv += Temp*Temp;
            Temp -= Sample::R(Sample::MirrorClamp, diffV, pos+int2{0,m});
            Rv += Temp*Temp;
        }
        
        float mv = 0;
        // Compute mv = mean_m FilteredV[i + m]
        if (!UseZhangCodeEst) mv = mom1/(2*M + 1);
        // Compute mv as in Zhang's MATLAB code
        else mv = Sample::R(filteredV, pos);
        
        pv = pv/(2*M) - mom1*mom1/(2*M*(2*M + 1));
        Rv = Rv/(2*M + 1) + DivEpsilon;
        float v = mv + (pv/(pv + Rv))*(Sample::R(diffV,pos)-mv);
        float V = pv - (pv/(pv + Rv))*pv + DivEpsilon;
        
        // Fuse the directional estimates to obtain the green component
        g = r + (V*h + H*v) / (H + V);
    
    } else {
        // This is a green pixel -- return its value directly
        g = r;
    }
    
    return float4(0, g, 0, 1);
}

fragment float CalcDiffGRGB(
    constant CFADesc& cfaDesc [[buffer(0)]],
    constant bool& modeGR [[buffer(1)]],
    texture2d<float> raw [[texture(0)]],
    texture2d<float> txt [[texture(1)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = cfaDesc.color(pos);
    if ((modeGR && c==CFAColor::Red) || (!modeGR && c==CFAColor::Blue)) {
        const float r = Sample::R(raw, pos);
        const float g = Sample::RGB(txt, pos).g;
        return g-r;
    }
    
    return 0;
}

float diagAvg(texture2d<float> txt, int2 pos) {
#define PX(d) Sample::R(Sample::MirrorClamp, txt, pos+(d))
    const int2 lu(-1,-1);
    const int2 ld(-1,+1);
    const int2 ru(+1,-1);
    const int2 rd(+1,+1);
    if (pos.y == 0) {
        if (pos.x == 0)
            return PX(rd);
        else if (pos.x < (int)txt.get_width()-1)
            return (PX(ld)+PX(rd))/2;
        else
            return PX(ld);
    
    } else if (pos.y < (int)txt.get_height()-1) {
        if (pos.x == 0)
            return (PX(ru)+PX(rd))/2;
        else if (pos.x < (int)txt.get_width()-1)
            return (PX(lu)+PX(ru)+PX(ld)+PX(rd))/4;
        else    
            return (PX(lu)+PX(ld))/2;
    
    } else {
        if (pos.x == 0)
            return PX(ru);
        else if (pos.x < (int)txt.get_width()-1)
            return (PX(lu)+PX(ru))/2;
        else
            return PX(lu);
    }
#undef PX
}

fragment float CalcDiagAvgDiffGRGB(
    constant CFADesc& cfaDesc [[buffer(0)]],
    constant bool& modeGR [[buffer(1)]],
    texture2d<float> raw [[texture(0)]],
    texture2d<float> txt [[texture(1)]],
    texture2d<float> diff [[texture(2)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = cfaDesc.color(pos);
    
    if ((modeGR && c==CFAColor::Blue) || (!modeGR && c==CFAColor::Red)) {
        return diagAvg(diff, pos);
    }
    
    // Pass-through
    return Sample::R(Sample::MirrorClamp, diff, pos);
}

float axialAvg(texture2d<float> txt, int2 pos) {
#define PX(d) Sample::R(Sample::MirrorClamp, txt, pos+(d))
    const int2 l(-1,+0);
    const int2 r(+1,+0);
    const int2 u(+0,-1);
    const int2 d(+0,+1);
    if (pos.y == 0) {
        if (pos.x == 0)
            return (PX(r)+PX(d))/2;
        else if (pos.x < (int)txt.get_width()-1)
            return (PX(l)+PX(r)+2*PX(d))/4;
        else
            return (PX(l)+PX(d))/2;
    
    } else if (pos.y < (int)txt.get_height()-1) {
        if (pos.x == 0)
            return (2*PX(r)+PX(u)+PX(d))/4;
        else if (pos.x < (int)txt.get_width()-1)
            return (PX(l)+PX(r)+PX(u)+PX(d))/4;
        else
            return (2*PX(l)+PX(u)+PX(d))/4;
    
    } else {
        if (pos.x == 0)
            return (PX(r)+PX(u))/2;
        else if (pos.x < (int)txt.get_width()-1)
            return (PX(l)+PX(r)+2*PX(u))/4;
        else
            return (PX(l)+PX(u))/2;
    }
#undef PX
}

fragment float CalcAxialAvgDiffGRGB(
    constant CFADesc& cfaDesc [[buffer(0)]],
    texture2d<float> raw [[texture(0)]],
    texture2d<float> txt [[texture(1)]],
    texture2d<float> diff [[texture(2)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = cfaDesc.color(pos);
    if (c == CFAColor::Green) return axialAvg(diff, pos);
    
    // Pass-through
    return Sample::R(diff, pos);
}

fragment float4 CalcRB(
    texture2d<float> txt [[texture(0)]],
    texture2d<float> diffGR [[texture(1)]],
    texture2d<float> diffGB [[texture(2)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float g = Sample::RGB(txt, pos).g;
    const float dgr = Sample::R(diffGR, pos);
    const float dgb = Sample::R(diffGB, pos);
    return float4(g-dgr, g, g-dgb, 1);
}

} // namespace DebayerLMMSE
} // namespace Shader
} // namespace ImagePipeline
} // namespace MDCTools
