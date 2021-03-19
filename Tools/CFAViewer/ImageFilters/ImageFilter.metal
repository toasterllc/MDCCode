#import <metal_stdlib>
#import "MetalUtil.h"
#import "ImageLayerTypes.h"
using namespace metal;
using namespace CFAViewer::MetalUtil;
using namespace CFAViewer::MetalUtil::Standard;
using namespace CFAViewer::ImageLayerTypes;
using namespace CFAViewer::ImageFilter;

namespace CFAViewer {
namespace Shader {
namespace ImageFilter {

vertex VertexOutput VertexShader(uint vidx [[vertex_id]]) {
    return Standard::VertexShader(vidx);
}

uint3 binFromColor(float3 color) {
    const uint32_t maxBin = (uint32_t)(sizeof(Histogram::r)/sizeof(*Histogram::r))-1;
    return {
        clamp((uint32_t)round(color.r*maxBin), (uint32_t)0, maxBin),
        clamp((uint32_t)round(color.g*maxBin), (uint32_t)0, maxBin),
        clamp((uint32_t)round(color.b*maxBin), (uint32_t)0, maxBin),
    };
}

float3 XYYFromXYZ(const float3 xyz) {
    const float denom = xyz[0] + xyz[1] + xyz[2];
    return {xyz[0]/denom, xyz[1]/denom, xyz[1]};
}

float3 XYZFromXYY(const float3 xyy) {
    const float X = (xyy[0]*xyy[2])/xyy[1];
    const float Y = xyy[2];
    const float Z = ((1.-xyy[0]-xyy[1])*xyy[2])/xyy[1];
    return {X,Y,Z};
}

fragment float LoadRaw(
    constant RenderContext& ctx [[buffer(0)]],
    constant ImagePixel* pxs [[buffer(1)]],
    device float3* samples [[buffer(2)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const float v = (float)pxs[ctx.imageWidth*pos.y + pos.x] / ImagePixelMax;
    if (pos.x >= (int)ctx.sampleRect.left &&
        pos.x < (int)ctx.sampleRect.right &&
        pos.y >= (int)ctx.sampleRect.top &&
        pos.y < (int)ctx.sampleRect.bottom) {
        const CFAColor c = ctx.cfaDesc.color(pos);
        const uint2 samplePos = {pos.x-ctx.sampleRect.left, pos.y-ctx.sampleRect.top};
        const float3 sample = float3(
            c==CFAColor::Red   ? v : 0.,
            c==CFAColor::Green ? v : 0.,
            c==CFAColor::Blue  ? v : 0.
        );
        samples[samplePos.y*ctx.sampleRect.width() + samplePos.x] = sample;
    }
    
    return v;
}

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

fragment float4 XYZD50FromCameraRaw(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 inputColor_cameraRaw = Sample::RGB(txt, int2(in.pos.xy));
    const float3x3 XYZD50_From_CameraRaw = ctx.colorMatrix;
    float3 outputColor_XYZD50 = XYZD50_From_CameraRaw * inputColor_cameraRaw;
    return float4(outputColor_XYZD50, 1);
}

fragment float4 XYYD50FromCameraRaw(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 inputColor_cameraRaw = Sample::RGB(txt, int2(in.pos.xy));
    const float3x3 XYZD50_From_CameraRaw = ctx.colorMatrix;
//    const float3x3 XYZD50_From_CameraRaw(1);
    const float3 c = XYYFromXYZ(XYZD50_From_CameraRaw * inputColor_cameraRaw);
    return float4(c, 1);
}

fragment float4 Exposure(
    constant RenderContext& ctx [[buffer(0)]],
    constant float& exposure [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    float3 c = Sample::RGB(txt, int2(in.pos.xy));
    c[2] *= exposure;
    return float4(c, 1);
}

fragment float4 Brightness(
    constant RenderContext& ctx [[buffer(0)]],
    constant float& brightness [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    float3 c = Sample::RGB(txt, int2(in.pos.xy));
    c[0] = 100*brightness + c[0]*(1-brightness);
    return float4(c, 1);
}

float bellcurve(float width, int plateau, float x) {
    return exp(-pow(width*x, plateau));
}

fragment float4 Contrast(
    constant RenderContext& ctx [[buffer(0)]],
    constant float& contrast [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    float3 c = Sample::RGB(txt, int2(in.pos.xy));
    const float k = 1+((bellcurve(2.7, 4, (c[0]/100)-.5))*contrast);
    c[0] = (k*(c[0]-50))+50;
    return float4(c, 1);
}

fragment float4 XYYD50FromXYZD50(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = Sample::RGB(txt, int2(in.pos.xy));
    return float4(XYYFromXYZ(c), 1);
}

fragment float4 XYZD50FromXYYD50(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = Sample::RGB(txt, int2(in.pos.xy));
    return float4(XYZFromXYY(c), 1);
}










float LabfInv(float x) {
    // From https://en.wikipedia.org/wiki/CIELAB_color_space
    const float d = 6./29;
    if (x > d)  return pow(x, 3);
    else        return 3*d*d*(x - 4./29);
}

float3 XYZFromLab(float3 white_XYZ, float3 c_Lab) {
    // From https://en.wikipedia.org/wiki/CIELAB_color_space
    const float k = (c_Lab.x+16)/116;
    const float X = white_XYZ.x * LabfInv(k+c_Lab.y/500);
    const float Y = white_XYZ.y * LabfInv(k);
    const float Z = white_XYZ.z * LabfInv(k-c_Lab.z/200);
    return float3(X,Y,Z);
}

float Labf(float x) {
    const float d = 6./29;
    const float d3 = d*d*d;
    if (x > d3) return pow(x, 1./3);
    else        return (x/(3*d*d)) + 4./29;
}

float3 LabFromXYZ(float3 white_XYZ, float3 c_XYZ) {
    const float k = Labf(c_XYZ.y/white_XYZ.y);
    const float L = 116*k - 16;
    const float a = 500*(Labf(c_XYZ.x/white_XYZ.x) - k);
    const float b = 200*(k - Labf(c_XYZ.z/white_XYZ.z));
    return float3(L,a,b);
}

fragment float4 LabD50FromXYZD50(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 D50(0.96422, 1.00000, 0.82521);
    return float4(LabFromXYZ(D50, Sample::RGB(txt, int2(in.pos.xy))), 1);
}

fragment float4 XYZD50FromLabD50(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 D50(0.96422, 1.00000, 0.82521);
    return float4(XYZFromLab(D50, Sample::RGB(txt, int2(in.pos.xy))), 1);
}

constant uint UIntNormalizeVal = 65535;
fragment float4 NormalizeXYYLuminance(
    constant RenderContext& ctx [[buffer(0)]],
    constant Vals3& maxValsXYY[[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float maxY = (float)maxValsXYY.z/UIntNormalizeVal;
    float3 c = Sample::RGB(txt, int2(in.pos.xy));
    c[2] /= maxY;
    return float4(c, 1);
}

fragment float4 NormalizeRGB(
    constant RenderContext& ctx [[buffer(0)]],
    constant Vals3& maxValsRGB[[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float denom = (float)max3(maxValsRGB.x, maxValsRGB.y, maxValsRGB.z)/UIntNormalizeVal;
    const float3 c = Sample::RGB(txt, int2(in.pos.xy)) / denom;
    return float4(c, 1);
}

fragment float4 LSRGBD65FromXYZD50(
    constant RenderContext& ctx [[buffer(0)]],
    device float3* samples [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c_XYZD50 = Sample::RGB(txt, int2(in.pos.xy));
    
    // From http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
    const float3x3 XYZD65_From_XYZD50 = transpose(float3x3(
        0.9555766,  -0.0230393, 0.0631636,
        -0.0282895, 1.0099416,  0.0210077,
        0.0122982,  -0.0204830, 1.3299098
    ));
    
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const float3x3 LSRGBD65_From_XYZD65 = transpose(float3x3(
        3.2404542,  -1.5371385, -0.4985314,
        -0.9692660, 1.8760108,  0.0415560,
        0.0556434,  -0.2040259, 1.0572252
    ));
    
    const float3 c_LSRGBD65 = LSRGBD65_From_XYZD65 * XYZD65_From_XYZD50 * c_XYZD50;
    
    const int2 pos = int2(in.pos.xy);
    if (pos.x >= (int)ctx.sampleRect.left &&
        pos.x < (int)ctx.sampleRect.right &&
        pos.y >= (int)ctx.sampleRect.top &&
        pos.y < (int)ctx.sampleRect.bottom) {
        const uint2 samplePos = {pos.x-ctx.sampleRect.left, pos.y-ctx.sampleRect.top};
        samples[samplePos.y*ctx.sampleRect.width() + samplePos.x] = c_XYZD50;
    }
    
    return float4(c_LSRGBD65, 1);
}




// Atomically sets the value at `dst` if `val` is greater than it
void setIfGreater(volatile device atomic_uint& dst, uint val) {
    uint current = (device uint&)dst;
    while (val > current) {
        if (atomic_compare_exchange_weak_explicit(&dst, &current, val,
            memory_order_relaxed, memory_order_relaxed)) break;
    }
}

fragment float4 FindMaxVals(
    constant RenderContext& ctx [[buffer(0)]],
    device Vals3& highlights [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 lsrgbfloat = Sample::RGB(txt, int2(in.pos.xy))*UIntNormalizeVal;
    const uint3 lsrgb(lsrgbfloat.x, lsrgbfloat.y, lsrgbfloat.z);
    
    setIfGreater((device atomic_uint&)highlights.x, lsrgb.r);
    setIfGreater((device atomic_uint&)highlights.y, lsrgb.g);
    setIfGreater((device atomic_uint&)highlights.z, lsrgb.b);
    
    return float4(lsrgbfloat, 1);
}


class Float3x3 {
public:
    Float3x3(texture2d<float> txt, int2 pos) {
        _c[0] = Sample::R(Sample::MirrorClamp, txt, pos+int2{-1,-1});
        _c[1] = Sample::R(Sample::MirrorClamp, txt, pos+int2{+0,-1});
        _c[2] = Sample::R(Sample::MirrorClamp, txt, pos+int2{+1,-1});
        
        _c[3] = Sample::R(Sample::MirrorClamp, txt, pos+int2{-1,+0});
        _c[4] = Sample::R(Sample::MirrorClamp, txt, pos+int2{+0,+0});
        _c[5] = Sample::R(Sample::MirrorClamp, txt, pos+int2{+1,+0});
        
        _c[6] = Sample::R(Sample::MirrorClamp, txt, pos+int2{-1,+1});
        _c[7] = Sample::R(Sample::MirrorClamp, txt, pos+int2{+0,+1});
        _c[8] = Sample::R(Sample::MirrorClamp, txt, pos+int2{+1,+1});
    }
    
    thread float& get(int x=0, int y=0) {
        return _c[((y+1)*3)+(x+1)];
    }
    
private:
    float _c[9];
};

fragment float ReconstructHighlights(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> rawTxt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = ctx.cfaDesc.color(pos);
    const CFAColor cn = ctx.cfaDesc.color(pos.x+1,pos.y);
    Float3x3 s(rawTxt, pos);
    
    float thresh = 1;
    
    // Short-circuit if this pixel isn't saturated
    if (s.get() < thresh) return s.get();
    
//    // Patch up the saturated values in `c`
//    if (red) {
//        //  Row0    G R G R
//        //  Row1    B G B G
//        //  Row2    G * G R
//        //  Row3    B G B G
//        if (c.get(-1,-1) >= thresh) c.get(-1,-1) = csat.b;
//        if (c.get(+0,-1) >= thresh) c.get(+0,-1) = csat.g;
//        if (c.get(+1,-1) >= thresh) c.get(+1,-1) = csat.b;
//        
//        if (c.get(-1,+0) >= thresh) c.get(-1,+0) = csat.g;
//        if (c.get(+0,+0) >= thresh) c.get(+0,+0) = csat.r;
//        if (c.get(+1,+0) >= thresh) c.get(+1,+0) = csat.g;
//        
//        if (c.get(-1,+1) >= thresh) c.get(-1,+1) = csat.b;
//        if (c.get(+0,+1) >= thresh) c.get(+0,+1) = csat.g;
//        if (c.get(+1,+1) >= thresh) c.get(+1,+1) = csat.b;
//    
//    } else if (greenr) {
//        //  Row0    G R G R
//        //  Row1    B G B G
//        //  Row2    G R * R
//        //  Row3    B G B G
//        if (c.get(-1,-1) >= thresh) c.get(-1,-1) = csat.g;
//        if (c.get(+0,-1) >= thresh) c.get(+0,-1) = csat.b;
//        if (c.get(+1,-1) >= thresh) c.get(+1,-1) = csat.g;
//        
//        if (c.get(-1,+0) >= thresh) c.get(-1,+0) = csat.r;
//        if (c.get(+0,+0) >= thresh) c.get(+0,+0) = csat.g;
//        if (c.get(+1,+0) >= thresh) c.get(+1,+0) = csat.r;
//        
//        if (c.get(-1,+1) >= thresh) c.get(-1,+1) = csat.g;
//        if (c.get(+0,+1) >= thresh) c.get(+0,+1) = csat.b;
//        if (c.get(+1,+1) >= thresh) c.get(+1,+1) = csat.g;
//    
//    } else if (greenb) {
//        //  Row0    G R G R
//        //  Row1    B * B G
//        //  Row2    G R G R
//        //  Row3    B G B G
//        if (c.get(-1,-1) >= thresh) c.get(-1,-1) = csat.g;
//        if (c.get(+0,-1) >= thresh) c.get(+0,-1) = csat.r;
//        if (c.get(+1,-1) >= thresh) c.get(+1,-1) = csat.g;
//        
//        if (c.get(-1,+0) >= thresh) c.get(-1,+0) = csat.b;
//        if (c.get(+0,+0) >= thresh) c.get(+0,+0) = csat.g;
//        if (c.get(+1,+0) >= thresh) c.get(+1,+0) = csat.b;
//        
//        if (c.get(-1,+1) >= thresh) c.get(-1,+1) = csat.g;
//        if (c.get(+0,+1) >= thresh) c.get(+0,+1) = csat.r;
//        if (c.get(+1,+1) >= thresh) c.get(+1,+1) = csat.g;
//    
//    } else if (blue) {
//        //  Row0    G R G R
//        //  Row1    B G * G
//        //  Row2    G R G R
//        //  Row3    B G B G
//        if (c.get(-1,-1) >= thresh) c.get(-1,-1) = csat.r;
//        if (c.get(+0,-1) >= thresh) c.get(+0,-1) = csat.g;
//        if (c.get(+1,-1) >= thresh) c.get(+1,-1) = csat.r;
//        
//        if (c.get(-1,+0) >= thresh) c.get(-1,+0) = csat.g;
//        if (c.get(+0,+0) >= thresh) c.get(+0,+0) = csat.b;
//        if (c.get(+1,+0) >= thresh) c.get(+1,+0) = csat.g;
//        
//        if (c.get(-1,+1) >= thresh) c.get(-1,+1) = csat.r;
//        if (c.get(+0,+1) >= thresh) c.get(+0,+1) = csat.g;
//        if (c.get(+1,+1) >= thresh) c.get(+1,+1) = csat.r;
//    }
//    
//    if (red) {
//        //  Row0    G R G R
//        //  Row1    B G B G
//        //  Row2    G * G R
//        //  Row3    B G B G
//        
//        const float r = ctx.highlightFactorR.r * (c.get(+0,+0));
//        const float g = ctx.highlightFactorR.g * (c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1));
//        const float b = ctx.highlightFactorR.b * (c.get(-1,-1)+c.get(-1,+1)+c.get(+1,-1)+c.get(+1,+1));
//        return (r+g+b)/9;
//    
//    } else if (greenr) {
//        //  Row0    G R G R
//        //  Row1    B G B G
//        //  Row2    G R * R
//        //  Row3    B G B G
//        
//        const float r = ctx.highlightFactorG.r * (c.get(-1,+0)+c.get(+1,+0));
//        const float g = ctx.highlightFactorG.g * (c.get(+0,+0)+c.get(-1,-1)+c.get(-1,+1)+c.get(+1,-1)+c.get(+1,+1));
//        const float b = ctx.highlightFactorG.b * (c.get(+0,-1)+c.get(+0,+1));
//        return (r+g+b)/9;
//    
//    } else if (greenb) {
//        //  Row0    G R G R
//        //  Row1    B * B G
//        //  Row2    G R G R
//        //  Row3    B G B G
//        
//        const float r = ctx.highlightFactorG.r * (c.get(+0,-1)+c.get(+0,+1));
//        const float g = ctx.highlightFactorG.g * (c.get(+0,+0)+c.get(-1,-1)+c.get(-1,+1)+c.get(+1,-1)+c.get(+1,+1));
//        const float b = ctx.highlightFactorG.b * (c.get(-1,+0)+c.get(+1,+0));
//        return (r+g+b)/9;
//    
//    } else if (blue) {
//        //  Row0    G R G R
//        //  Row1    B G * G
//        //  Row2    G R G R
//        //  Row3    B G B G
//        
//        const float r = ctx.highlightFactorB.r * (c.get(-1,-1)+c.get(-1,+1)+c.get(+1,-1)+c.get(+1,+1));
//        const float g = ctx.highlightFactorB.g * (c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1));
//        const float b = ctx.highlightFactorB.b * (c.get(+0,+0));
//        return (r+g+b)/9;
//    }
//    
//    return 0;
    
    //  Row0    G R G R
    //  Row1    B G B G
    //  Row2    G R G R
    //  Row3    B G B G
    
    uint goodCount = 0;
    if (s.get(-1,+0) < thresh) goodCount++;
    if (s.get(+1,+0) < thresh) goodCount++;
    if (s.get(+0,-1) < thresh) goodCount++;
    if (s.get(+0,+1) < thresh) goodCount++;
    if (goodCount == 0) {
        switch (c) {
        case CFAColor::Red:     s.get() *= 1.1300929235; break;
        case CFAColor::Green:   s.get() *= 1.6132952108; break;
        case CFAColor::Blue:    s.get() *= 1; break;
        }
        
    } else {
        if (c == CFAColor::Red) {
//            uint gcount = 0;
//            float g = 0;
//            if (c.get(-1,-1) < thresh) { g += c.get(-1,-1); gcount++; };
//            if (c.get(+1,-1) < thresh) { g += c.get(+1,-1); gcount++; };
//            if (c.get(-1,+1) < thresh) { g += c.get(-1,+1); gcount++; };
//            if (c.get(+1,+1) < thresh) { g += c.get(+1,+1); gcount++; };
//            g /= gcount;
//            
//            uint bcount = 0;
//            float b = 0;
//            if (c.get(-1,+0) < thresh) { g += c.get(-1,+0); bcount++; };
//            if (c.get(+1,+0) < thresh) { g += c.get(+1,+0); bcount++; };
//            if (c.get(+0,-1) < thresh) { g += c.get(+0,-1); bcount++; };
//            if (c.get(+0,+1) < thresh) { g += c.get(+0,+1); bcount++; };
//            b /= bcount;
//            
//            if (gcount && bcount) {
//                c.get() = (ctx.highlightFactorR.g*g) + (ctx.highlightFactorR.b*b);
//            } else if (gcount) {
//                c.get() = (ctx.highlightFactorR.g*g);
//            } else if (bcount) {
//                c.get() = (ctx.highlightFactorR.b*b);
//            }
            
//            c.get() =   ctx.highlightFactorR.r*(c.get(-1,-1)+c.get(+1,-1)+c.get(-1,+1)+c.get(+1,+1))/8 +
//                        ctx.highlightFactorR.g*(c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1))/8;
            s.get() = 1.051*(s.get(-1,+0)+s.get(+1,+0)+s.get(+0,-1)+s.get(+0,+1))/4;
        
        } else if (c==CFAColor::Green && cn==CFAColor::Red) {
//            c.get() = ctx.highlightFactorR.g*(c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1))/4;
            s.get() = 1.544*(s.get(-1,+0)+s.get(+1,+0)+s.get(+0,-1)+s.get(+0,+1))/4;
        
        } else if (c==CFAColor::Green && cn==CFAColor::Blue) {
//            c.get() = ctx.highlightFactorR.b*(c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1))/4;
            s.get() = 1.544*(s.get(-1,+0)+s.get(+1,+0)+s.get(+0,-1)+s.get(+0,+1))/4;
        
        } else if (c == CFAColor::Blue) {
//            c.get() = ctx.highlightFactorG.r*(c.get(-1,+0)+c.get(+1,+0)+c.get(+0,-1)+c.get(+0,+1))/4;
            s.get() = 1.195*(s.get(-1,+0)+s.get(+1,+0)+s.get(+0,-1)+s.get(+0,+1))/4;
        }
    }
    return s.get();
}

fragment float4 SRGBGamma(
    constant RenderContext& ctx [[buffer(0)]],
    device float3* samples [[buffer(1)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c_LSRGB = Sample::RGB(txt, int2(in.pos.xy));
    float3 c_SRGB = float3{
        SRGBGammaForward(c_LSRGB.r),
        SRGBGammaForward(c_LSRGB.g),
        SRGBGammaForward(c_LSRGB.b)
    };
    
    const int2 pos = int2(in.pos.xy);
    if (pos.x >= (int)ctx.sampleRect.left &&
        pos.x < (int)ctx.sampleRect.right &&
        pos.y >= (int)ctx.sampleRect.top &&
        pos.y < (int)ctx.sampleRect.bottom) {
        const uint2 samplePos = {pos.x-ctx.sampleRect.left, pos.y-ctx.sampleRect.top};
        samples[samplePos.y*ctx.sampleRect.width() + samplePos.x] = c_SRGB;
    }
    
    return float4(c_SRGB, 1);
}

fragment float4 Display(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = Sample::RGB(txt, int2(in.pos.xy));
    return float4(c, 1);
}

fragment float4 DisplayR(
    constant RenderContext& ctx [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float c = Sample::R(txt, int2(in.pos.xy));
    return float4(c, c, c, 1);
}

} // namespace ImageLayer
} // namespace Shader
} // namespace CFAViewer
