#import <metal_stdlib>
#import "ImagePipelineTypes.h"
#import "Code/Lib/Toastbox/Mac/CFA.h"
#import "Code/Lib/Toastbox/Mac/MetalUtil.h"
using namespace metal;
using namespace MDCTools;
using namespace ImagePipeline;
using namespace Toastbox;
using namespace Toastbox::MetalUtil;

namespace ImagePipeline {
namespace Shader {
namespace Base {

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

//// TODO: switch to renderer.textureWrite()
//fragment float LoadRaw(
//    constant CFADesc& cfaDesc [[buffer(0)]],
//    constant uint32_t& imageWidth [[buffer(1)]],
//    constant uint32_t& imageHeight [[buffer(2)]],
//    constant ImagePixel* pxs [[buffer(3)]],
//    VertexOutput in [[stage_in]]
//) {
//    const int2 pos = int2(in.pos.xy);
//    const float v = (float)pxs[imageWidth*pos.y + pos.x] / ImagePixelMax;
//    return v;
//}

fragment void SampleRaw(
    constant CFADesc& cfaDesc [[buffer(0)]],
    constant SampleRect& sampleRect [[buffer(1)]],
    device float3* samples [[buffer(2)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    if (sampleRect.contains(pos)) {
        const CFAColor c = cfaDesc.color(pos);
        const int2 spos = {pos.x-sampleRect.left, pos.y-sampleRect.top};
        const float3 s = float3(
            c==CFAColor::Red   ? Sample::R(raw, pos) : 0.,
            c==CFAColor::Green ? Sample::R(raw, pos) : 0.,
            c==CFAColor::Blue  ? Sample::R(raw, pos) : 0.
        );
        samples[spos.y*sampleRect.width() + spos.x] = s;
    }
}

fragment void SampleRGB(
    constant CFADesc& cfaDesc [[buffer(0)]],
    constant SampleRect& sampleRect [[buffer(1)]],
    device float3* samples [[buffer(2)]],
    texture2d<float> rgb [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    if (sampleRect.contains(pos)) {
        const int2 samplePos = {pos.x-sampleRect.left, pos.y-sampleRect.top};
        samples[samplePos.y*sampleRect.width() + samplePos.x] = Sample::RGB(rgb, pos);
    }
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

fragment float4 XYZD50FromCamRaw(
    constant float3x3& colorMatrix [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 inputColor_camRaw = Sample::RGB(txt, int2(in.pos.xy));
    const float3x3 XYZD50_From_CamRaw = colorMatrix;
    float3 outputColor_XYZD50 = XYZD50_From_CamRaw * inputColor_camRaw;
    return float4(outputColor_XYZD50, 1);
}

fragment float4 XYYD50FromCamRaw(
    constant float3x3& colorMatrix [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 inputColor_camRaw = Sample::RGB(txt, int2(in.pos.xy));
    const float3x3 XYZD50_From_CamRaw = colorMatrix;
//    const float3x3 XYZD50_From_CamRaw(1);
    const float3 c = XYYFromXYZ(XYZD50_From_CamRaw * inputColor_camRaw);
    return float4(c, 1);
}

fragment float WhiteBalanceRaw(
    constant CFADesc& cfaDesc [[buffer(0)]],
    constant float3& wb [[buffer(1)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const int2 pos = int2(in.pos.xy);
    const CFAColor c = cfaDesc.color(pos);
    const float s = Sample::R(raw, pos);
    switch (c) {
    case CFAColor::Red:     return wb.r*s;
    case CFAColor::Green:   return wb.g*s;
    case CFAColor::Blue:    return wb.b*s;
    }
}

fragment float4 WhiteBalanceRGB(
    constant float3& wb [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    return float4(wb*Sample::RGB(txt, int2(in.pos.xy)), 1);
}


//fragment float4 WhiteBalance(
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const float3x3 wb(
//        1, 0, 0,
//        0, 1, 0,
//        0, 0, 1
//    );
//    
////    const float3x3 wb(
////        1.4174, 0, 0,
////        0, 1, 0,
////        0, 0, 1.0887
////    );
//    
////    // image000010_sensorname_ChengCanon600D.png: C5 white balance
////    const float3x3 wb(
////        1.7859, 0, 0,
////        0,      1, 0,
////        0,      0, 1.3184
////    );
//    
//    // ColorCheckerRaw: manual white balance
////    const float3x3 wb(
////        1.015462, 0.000000, 0.000000,
////        0.000000, 1.000000, 0.000000,
////        0.000000, 0.000000, 2.551048
////    );
//    
////    // image001_sensorname_AR0330.png: C5 white balance
////    const float3x3 wb(
////        1.307648, 0.000000, 0.000000,
////        0.000000, 1.000000, 0.000000,
////        0.000000, 0.000000, 1.275692
////    );
//    
//    const float3 c = Sample::RGB(txt, int2(in.pos.xy));
//    return float4(wb*c, 1);
//}

fragment float4 ApplyColorMatrix(
    constant float3x3& colorMatrix [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = Sample::RGB(txt, int2(in.pos.xy));
    return float4(colorMatrix*c, 1);
}

fragment float4 Exposure(
    constant float& exposure [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    float3 c = Sample::RGB(txt, int2(in.pos.xy));
    c[2] *= exposure;
    return float4(c, 1);
}

fragment float4 Brightness(
    constant float& brightness [[buffer(0)]],
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
    constant float& contrast [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    float3 c = Sample::RGB(txt, int2(in.pos.xy));
    const float k = 1+((bellcurve(2.7, 4, (c[0]/100)-.5))*contrast);
    c[0] = (k*(c[0]-50))+50;
    return float4(c, 1);
}

fragment float4 XYYFromXYZ(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = Sample::RGB(txt, int2(in.pos.xy));
    return float4(XYYFromXYZ(c), 1);
}

fragment float4 XYZFromXYY(
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
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 D50(0.96422, 1.00000, 0.82521);
    return float4(LabFromXYZ(D50, Sample::RGB(txt, int2(in.pos.xy))), 1);
}

fragment float4 XYZD50FromLabD50(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 D50(0.96422, 1.00000, 0.82521);
    return float4(XYZFromLab(D50, Sample::RGB(txt, int2(in.pos.xy))), 1);
}

constant uint UIntNormalizeVal = 65535;
fragment float4 NormalizeXYYLuminance(
    constant Vals3& maxValsXYY[[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float maxY = (float)maxValsXYY.z/UIntNormalizeVal;
    float3 c = Sample::RGB(txt, int2(in.pos.xy));
    c[2] /= maxY;
    return float4(c, 1);
}

fragment float4 NormalizeRGB(
    constant Vals3& maxValsRGB[[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float denom = (float)max3(maxValsRGB.x, maxValsRGB.y, maxValsRGB.z)/UIntNormalizeVal;
    const float3 c = Sample::RGB(txt, int2(in.pos.xy)) / denom;
    return float4(c, 1);
}

fragment float4 BradfordXYZD65FromXYZD50(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    // From http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
    const float3x3 M = transpose(float3x3(
        0.9555766,  -0.0230393, 0.0631636,
        -0.0282895, 1.0099416,  0.0210077,
        0.0122982,  -0.0204830, 1.3299098
    ));
    return float4(M*Sample::RGB(txt, int2(in.pos.xy)), 1);
}

fragment float4 BradfordXYZD50FromXYZD65(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    // From http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
    const float3x3 M = transpose(float3x3(
        1.0478112,  0.0228866,  -0.0501270,
         0.0295424, 0.9904844,  -0.0170491,
        -0.0092345, 0.0150436,  0.7521316
    ));
    return float4(M*Sample::RGB(txt, int2(in.pos.xy)), 1);
}


fragment float4 LSRGBD65FromXYZD65(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const float3x3 M = transpose(float3x3(
        3.2404542,  -1.5371385, -0.4985314,
        -0.9692660, 1.8760108,  0.0415560,
        0.0556434,  -0.2040259, 1.0572252
    ));
    return float4(M * Sample::RGB(txt, int2(in.pos.xy)), 1);
}


fragment float4 XYZD65FromLSRGBD65(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const float3x3 M = transpose(float3x3(
        0.4124564,  0.3575761,  0.1804375,
        0.2126729,  0.7151522,  0.0721750,
        0.0193339,  0.1191920,  0.9503041
    ));
    return float4(M * Sample::RGB(txt, int2(in.pos.xy)), 1);
}

fragment float4 XYZD50FromProPhotoRGB(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const float3x3 M = transpose(float3x3(
        0.7976749,  0.1351917,  0.0313534,
        0.2880402,  0.7118741,  0.0000857,
        0.0000000,  0.0000000,  0.8252100
    ));
    return float4(M * Sample::RGB(txt, int2(in.pos.xy)), 1);
}

fragment float4 ProPhotoRGBFromXYZD50(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const float3x3 M = transpose(float3x3(
        1.3459433,  -0.2556075, -0.0511118,
        -0.5445989, 1.5081673,  0.0205351,
        0.0000000,  0.0000000,  1.2118128
    ));
    return float4(M * Sample::RGB(txt, int2(in.pos.xy)), 1);
}

//fragment float4 XYZD50FromLSRGBD65(
//    constant SampleRect& sampleRect [[buffer(0)]],
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const float3 c_LSRGBD65 = Sample::RGB(txt, int2(in.pos.xy));
//    
//    // From http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
//    const float3x3 XYZD50_From_XYZD65 = transpose(float3x3(
//        
//    ));
//    
//    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
//    const float3x3 XYZD65_From_LSRGBD65 = transpose(float3x3(
//        3.2404542,  -1.5371385, -0.4985314,
//        -0.9692660, 1.8760108,  0.0415560,
//        0.0556434,  -0.2040259, 1.0572252
//    ));
//    
//    const float3 c_XYZD50 = LSRGBD65_From_XYZD65 * XYZD65_From_XYZD50 * c_LSRGBD65;
//    return float4(c_XYZD50, 1);
//}




// Atomically sets the value at `dst` if `val` is greater than it
void setIfGreater(volatile device atomic_uint& dst, uint val) {
    uint current = (device uint&)dst;
    while (val > current) {
        if (atomic_compare_exchange_weak_explicit(&dst, &current, val,
            memory_order_relaxed, memory_order_relaxed)) break;
    }
}

fragment float4 FindMaxVals(
    device Vals3& highlights [[buffer(0)]],
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

fragment float4 SRGBGamma(
    constant SampleRect& sampleRect [[buffer(0)]],
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c_LSRGB = Sample::RGB(txt, int2(in.pos.xy));
    const float3 c_SRGB = float3{
        SRGBGammaForward(c_LSRGB.r),
        SRGBGammaForward(c_LSRGB.g),
        SRGBGammaForward(c_LSRGB.b)
    };
    return float4(c_SRGB, 1);
}

fragment float4 Display(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float3 c = Sample::RGB(txt, int2(in.pos.xy));
    return float4(c, 1);
}

fragment float4 DisplayR(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    const float c = Sample::R(txt, int2(in.pos.xy));
    return float4(c, c, c, 1);
}

fragment float4 DebayerDownsample(
    constant CFADesc& cfaDesc [[buffer(0)]],
    constant uint32_t& targetWidth [[buffer(1)]],
    constant uint32_t& targetHeight [[buffer(2)]],
    texture2d<float> raw [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    // `halfPxOff` is the .5 offset converted to unity coordinates
    const float2 halfPxOff = float2(.5)/float2(targetWidth, targetHeight);
    // Convert unity position -> integer coords for `raw`
    const int2 pos = int2(round((in.posUnit.xy-halfPxOff) * float2(raw.get_width(), raw.get_height())));
    const CFAColor c = cfaDesc.color(pos);
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

vertex VertexOutput TimestampVertexShader(
    constant TimestampContext& ctx [[buffer(0)]],
    uint vidx [[vertex_id]]
) {
    float2 off = (2*ctx.timestampOffset)-1;
    VertexOutput r = {
        .pos = float4(off + (2*SquareVert[vidx] * ctx.timestampSize), 0, 1),
        .posUnit = SquareVertYFlipped[vidx],
    };
    return r;
}

fragment float4 TimestampFragmentShader(
    texture2d<float> txt [[texture(0)]],
    VertexOutput in [[stage_in]]
) {
    return txt.sample({}, in.posUnit);
}

} // namespace Base
} // namespace Shader
} // namespace ImagePipeline
