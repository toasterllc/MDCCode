#import <metal_stdlib>
#import "ImageGridLayerTypes.h"
#import "Tools/Shared/MetalUtil.h"
using namespace metal;
using namespace MDCTools::MetalUtil;
using namespace MDCStudio::ImageGridLayerTypes;

namespace MDCStudio {
namespace ImageGridLayerShader {

struct VertexOutput {
    uint idx;
    float4 posView [[position]];
    float2 posPx;
};

static constexpr constant float2 _Verts[6] = {
    {0, 0},
    {0, 1},
    {1, 0},
    {1, 0},
    {0, 1},
    {1, 1},
};

vertex VertexOutput VertexShader(
    constant RenderContext& ctx [[buffer(0)]],
    constant ImageRecordRef* imageRecordRefs [[buffer(1)]],
    uint vidx [[vertex_id]],
    uint iidx [[instance_id]]
) {
    const uint relIdx = iidx; // Index within chunk
    const uint absIdx = ctx.idxOff + relIdx;
    const Grid::Rect rect = ctx.grid.rectForCellIndex(absIdx);
    const int2 voff = int2(rect.size.x, rect.size.y) * int2(_Verts[vidx]);
    const int2 vabs = int2(rect.point.x, rect.point.y) + voff;
    const float2 vnorm = float2(vabs) / ctx.viewSize;
    
    return VertexOutput{
        .idx = relIdx,
        .posView = ctx.transform * float4(vnorm, 0, 1),
        .posPx = float2(voff),
    };
}

static float4 blendOver(float4 a, float4 b) {
    const float oa = a.a + b.a*(1-a.a);
    if (oa == 0) return 0;
    const float3 oc = (a.rgb*a.a + b.rgb*b.a*(1-a.a)) / oa;
    return float4(oc, oa);
}

static float4 blendColorDodge(float4 a, float4 b) {
    if (a.a == 0) return b;
    const float3 oc = min(float3(1), b.rgb / (float3(1)-a.rgb)); // min to prevent nan/infinity
    return float4(oc, a.a);
}

static float4 blendMask(float mask, float4 a) {
    return float4(a.rgb, a.a*mask);
}



float3 XYZD50FromProPhotoRGB(float3 c) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const float3x3 M = transpose(float3x3(
        0.7976749,  0.1351917,  0.0313534,
        0.2880402,  0.7118741,  0.0000857,
        0.0000000,  0.0000000,  0.8252100
    ));
    return M*c;
}

float3 BradfordXYZD65FromXYZD50(float3 c) {
    // From http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
    const float3x3 M = transpose(float3x3(
        0.9555766,  -0.0230393, 0.0631636,
        -0.0282895, 1.0099416,  0.0210077,
        0.0122982,  -0.0204830, 1.3299098
    ));
    return M*c;
}

float3 LSRGBD65FromXYZD65(float3 c) {
    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
    const float3x3 M = transpose(float3x3(
        3.2404542,  -1.5371385, -0.4985314,
        -0.9692660, 1.8760108,  0.0415560,
        0.0556434,  -0.2040259, 1.0572252
    ));
    return M*c;
}

float3 XYYFromXYZ(float3 xyz) {
    const float denom = xyz[0] + xyz[1] + xyz[2];
    return {xyz[0]/denom, xyz[1]/denom, xyz[1]};
}

float3 XYZFromXYY(float3 xyy) {
    const float X = (xyy[0]*xyy[2])/xyy[1];
    const float Y = xyy[2];
    const float Z = ((1.-xyy[0]-xyy[1])*xyy[2])/xyy[1];
    return {X,Y,Z};
}

float Labf(float x) {
    const float d = 6./29;
    const float d3 = d*d*d;
    if (x > d3) return pow(x, 1./3);
    else        return (x/(3*d*d)) + 4./29;
}

float LabfInv(float x) {
    // From https://en.wikipedia.org/wiki/CIELAB_color_space
    const float d = 6./29;
    if (x > d)  return pow(x, 3);
    else        return 3*d*d*(x - 4./29);
}

float3 LabFromXYZ(float3 white_XYZ, float3 c_XYZ) {
    const float k = Labf(c_XYZ.y/white_XYZ.y);
    const float L = 116*k - 16;
    const float a = 500*(Labf(c_XYZ.x/white_XYZ.x) - k);
    const float b = 200*(k - Labf(c_XYZ.z/white_XYZ.z));
    return float3(L,a,b);
}

float3 XYZFromLab(float3 white_XYZ, float3 c_Lab) {
    // From https://en.wikipedia.org/wiki/CIELAB_color_space
    const float k = (c_Lab.x+16)/116;
    const float X = white_XYZ.x * LabfInv(k+c_Lab.y/500);
    const float Y = white_XYZ.y * LabfInv(k);
    const float Z = white_XYZ.z * LabfInv(k-c_Lab.z/200);
    return float3(X,Y,Z);
}

float3 LabD50FromXYZD50(float3 xyz) {
    const float3 D50(0.96422, 1.00000, 0.82521);
    return LabFromXYZ(D50, xyz);
}

float3 XYZD50FromLabD50(float3 lab) {
    const float3 D50(0.96422, 1.00000, 0.82521);
    return XYZFromLab(D50, lab);
}

float3 Exposure(float exposure, float3 c) {
    c[2] *= pow(2, exposure);
    return c;
}

float3 Brightness(float brightness, float3 c) {
    c[0] = 100*brightness + c[0]*(1-brightness);
    return c;
}

float bellcurve(float width, int plateau, float x) {
    return exp(-pow(width*x, plateau));
}

float3 Contrast(float contrast, float3 c) {
    const float k = 1+((bellcurve(2.7, 4, (c[0]/100)-.5))*contrast);
    c[0] = (k*(c[0]-50))+50;
    return c;
}







float Luv_u(float3 c_XYZ) {
    return 4*c_XYZ.x/(c_XYZ.x+15*c_XYZ.y+3*c_XYZ.z);
}

float Luv_v(float3 c_XYZ) {
    return 9*c_XYZ.y/(c_XYZ.x+15*c_XYZ.y+3*c_XYZ.z);
}

float3 LuvFromXYZ(float3 white_XYZ, float3 c_XYZ) {
    const float k1 = 24389./27;
    const float k2 = 216./24389;
    const float y = c_XYZ.y/white_XYZ.y;
    const float L = (y<=k2 ? k1*y : 116*pow(y, 1./3)-16);
    const float u_ = Luv_u(c_XYZ);
    const float v_ = Luv_v(c_XYZ);
    const float uw_ = Luv_u(white_XYZ);
    const float vw_ = Luv_v(white_XYZ);
    const float u = 13*L*(u_-uw_);
    const float v = 13*L*(v_-vw_);
    return {L,u,v};
}

float3 XYZFromLuv(float3 white_XYZ, float3 c_Luv) {
    const float uw_ = Luv_u(white_XYZ);
    const float vw_ = Luv_v(white_XYZ);
    const float u_ = c_Luv[1]/(13*c_Luv[0]) + uw_;
    const float v_ = c_Luv[2]/(13*c_Luv[0]) + vw_;
    const float Y = white_XYZ.y*(c_Luv[0]<=8 ? c_Luv[0]*(27./24389) : pow((c_Luv[0]+16)/116, 3));
    const float X = Y*(9*u_)/(4*v_);
    const float Z = Y*(12-3*u_-20*v_)/(4*v_);
    return {X,Y,Z};
}

float3 LuvD50FromXYZD50(float3 c) {
    const float3 D50_XYZ(0.96422, 1.00000, 0.82521);
    return LuvFromXYZ(D50_XYZ, c);
}

float3 XYZD50FromLuvD50(float3 c) {
    const float3 D50_XYZ(0.96422, 1.00000, 0.82521);
    return XYZFromLuv(D50_XYZ, c);
}

float3 LCHuvFromLuv(float3 c_Luv) {
    const float L = c_Luv[0];
    const float C = sqrt(c_Luv[1]*c_Luv[1] + c_Luv[2]*c_Luv[2]);
    const float H = atan2(c_Luv[2], c_Luv[1]);
    return {L,C,H};
}

float3 LuvFromLCHuv(float3 c_LCHuv) {
    const float L = c_LCHuv[0];
    const float u = c_LCHuv[1]*cos(c_LCHuv[2]);
    const float v = c_LCHuv[1]*sin(c_LCHuv[2]);
    return {L,u,v};
}

float3 Saturation(float saturation, float3 c) {
    c = LuvD50FromXYZD50(c);
    c = LCHuvFromLuv(c);
    c[1] *= pow(2, 2*saturation);
    c = LuvFromLCHuv(c);
    c = XYZD50FromLuvD50(c);
    return c;
}



//
//float3 XYZFromXYY(const float3 xyy) {
//    const float X = (xyy[0]*xyy[2])/xyy[1];
//    const float Y = xyy[2];
//    const float Z = ((1.-xyy[0]-xyy[1])*xyy[2])/xyy[1];
//    return {X,Y,Z};
//}
//
//fragment float4 Exposure(
//    constant float& exposure [[buffer(0)]],
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    float3 c = Sample::RGB(txt, int2(in.pos.xy));
//    c[2] *= exposure;
//    return float4(c, 1);
//}
//
//
//fragment float4 LabD50FromXYZD50(
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const float3 D50(0.96422, 1.00000, 0.82521);
//    return float4(LabFromXYZ(D50, Sample::RGB(txt, int2(in.pos.xy))), 1);
//}
//
//fragment float4 Brightness(
//    constant float& brightness [[buffer(0)]],
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    float3 c = Sample::RGB(txt, int2(in.pos.xy));
//    c[0] = 100*brightness + c[0]*(1-brightness);
//    return float4(c, 1);
//}
//
//fragment float4 Contrast(
//    constant float& contrast [[buffer(0)]],
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    float3 c = Sample::RGB(txt, int2(in.pos.xy));
//    const float k = 1+((bellcurve(2.7, 4, (c[0]/100)-.5))*contrast);
//    c[0] = (k*(c[0]-50))+50;
//    return float4(c, 1);
//}
//
//fragment float4 XYZD50FromLabD50(
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    const float3 D50(0.96422, 1.00000, 0.82521);
//    return float4(XYZFromLab(D50, Sample::RGB(txt, int2(in.pos.xy))), 1);
//}
//
//fragment float4 BradfordXYZD65FromXYZD50(
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    // From http://www.brucelindbloom.com/index.html?Eqn_ChromAdapt.html
//    const float3x3 M = transpose(float3x3(
//        0.9555766,  -0.0230393, 0.0631636,
//        -0.0282895, 1.0099416,  0.0210077,
//        0.0122982,  -0.0204830, 1.3299098
//    ));
//    return float4(M*Sample::RGB(txt, int2(in.pos.xy)), 1);
//}
//
//fragment float4 LSRGBD65FromXYZD65(
//    texture2d<float> txt [[texture(0)]],
//    VertexOutput in [[stage_in]]
//) {
//    // From http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
//    const float3x3 M = transpose(float3x3(
//        3.2404542,  -1.5371385, -0.4985314,
//        -0.9692660, 1.8760108,  0.0415560,
//        0.0556434,  -0.2040259, 1.0572252
//    ));
//    return float4(M * Sample::RGB(txt, int2(in.pos.xy)), 1);
//}

struct [[gnu::packed]] ImageOptions {
    enum class Rotation : uint8_t {
        Clockwise0,
        Clockwise90,
        Clockwise180,
        Clockwise270,
    };
    
    enum class Corner : uint8_t {
        BottomRight,
        BottomLeft,
        TopLeft,
        TopRight,
    };
    
    Rotation rotation = Rotation::Clockwise0;
    bool defringe = false;
    bool reconstructHighlights = false;
    struct [[gnu::packed]] {
        bool show = false;
        Corner corner = Corner::BottomRight;
    } timestamp;
    uint8_t _pad[3];
    
    struct [[gnu::packed]] {
        bool automatic = false;
        uint8_t _pad[3];
        float value = 0;
    } whiteBalance;
    
    float exposure = 0;
    float saturation = 0;
    float brightness = 0;
    float contrast = 0;
    struct {
        float amount = 0;
        float radius = 0;
    } localContrast;
    
    // _reserved: so we can add fields in the future without doing a data migration
    uint8_t _reserved[64] = {};
};



static float3 ColorAdjustments(device const ImageOptions& opts, float3 c) {
    // XYZD50 <- ProPhotoRGB
    c = XYZD50FromProPhotoRGB(c);
    // XYY.D50 <- XYZ.D50
    c = XYYFromXYZ(c);
        // Exposure
        c = Exposure(opts.exposure, c);
    // XYZ.D50 <- XYY.D50
    c = XYZFromXYY(c);
    
    // Lab.D50 <- XYZ.D50
    c = LabD50FromXYZD50(c);
        c = Brightness(opts.brightness, c);
        c = Contrast(opts.contrast, c);
    // XYZ.D50 <- Lab.D50
    c = XYZD50FromLabD50(c);
        c = Saturation(opts.saturation, c);
    
//        // XYZ.D50 -> Lab.D50
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::LabD50FromXYZD50",
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // Brightness
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::Brightness",
//                    // Buffer args
//                    opts.brightness,
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // Contrast
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::Contrast",
//                    // Buffer args
//                    opts.contrast,
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // Lab.D50 -> XYZ.D50
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYZD50FromLabD50",
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // Saturation
//        Saturation::Run(renderer, opts.saturation, rgb);
    
    
    
    // XYZ.D65 <- XYZ.D50
    c = BradfordXYZD65FromXYZD50(c);
    // LSRGB.D65 <- XYZ.D65
    c = LSRGBD65FromXYZD65(c);
    return c;
    
//        // ProPhotoRGB -> XYZ.D50
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYZD50FromProPhotoRGB",
//                    // Texture args
//                    rgb
//                )
//            );
//        }
    
    
//    return c*(opts.brightness+.1);
//    return c;

//        // White balance
//        {
//            const double factor = std::max(std::max(illum[0], illum[1]), illum[2]);
//            const Mat<double,3,1> wb(factor/illum[0], factor/illum[1], factor/illum[2]);
//            const simd::float3 simdWB = simdForMat(wb);
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::WhiteBalance2",
//                    // Buffer args
//                    simdWB,
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // Camera raw -> ProPhotoRGB
//        {
//            const CCM ccm = CCMForIlluminant(illum);
////            printf("CCT: %f\n", ccm.cct);
//            const simd::float3x3 colorMatrix = simdForMat(ccm.m);
//            
////            const simd::float3x3 colorMatrix = simdForMat(opts.colorMatrix);
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::ApplyColorMatrix",
//                    // Buffer args
//                    colorMatrix,
//                    // Texture args
//                    rgb
//                )
//            );
//        }
        
//        // ProPhotoRGB -> XYZ.D50
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYZD50FromProPhotoRGB",
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // XYZ.D50 -> XYY.D50
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYYFromXYZ",
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // Exposure
//        {
//            const float exposure = pow(2, opts.exposure);
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::Exposure",
//                    // Buffer args
//                    exposure,
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // XYY.D50 -> XYZ.D50
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYZFromXYY",
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // XYZ.D50 -> Lab.D50
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::LabD50FromXYZD50",
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // Brightness
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::Brightness",
//                    // Buffer args
//                    opts.brightness,
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // Contrast
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::Contrast",
//                    // Buffer args
//                    opts.contrast,
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // Lab.D50 -> XYZ.D50
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYZD50FromLabD50",
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // Saturation
//        Saturation::Run(renderer, opts.saturation, rgb);
//        
//        // XYZ.D50 -> XYZ.D65
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::BradfordXYZD65FromXYZD50",
//                    // Texture args
//                    rgb
//                )
//            );
//        }
//        
//        // XYZ.D65 -> LSRGB.D65
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::LSRGBD65FromXYZD65",
//                    // Texture args
//                    rgb
//                )
//            );
//        }

}



fragment float4 FragmentShader(
    constant RenderContext& ctx [[buffer(0)]],
    device uint8_t* images [[buffer(1)]],
    device bool* selectedImageIds [[buffer(2)]],
    texture2d<float> maskTxt [[texture(0)]],
    texture2d<float> outlineTxt [[texture(1)]],
    texture2d<float> shadowTxt [[texture(2)]],
    texture2d<float> selectionTxt [[texture(4)]],
    VertexOutput in [[stage_in]]
) {
    #warning TODO: adding +.5 to the pixel coordinates supplied to shadowTxt.sample() causes incorrect results. does that mean that the Sample::RGBA() implementation is incorrect? or are we getting bad pixel coords via `VertexOutput in`?
    
    device uint8_t* imageBuf = images+ctx.imagesOff+(ctx.imageSize*in.idx);
    const uint32_t imageId = *((device uint32_t*)(imageBuf+ctx.off.id));
    device const ImageOptions& imageOpts = *((device const ImageOptions*)(imageBuf+ctx.off.options));
    device uint8_t* thumbData = imageBuf+ctx.off.thumbData;
    
    const uint32_t thumbInset = (shadowTxt.get_width()-maskTxt.get_width())/2;
    const int2 pos = int2(in.posPx)-int2(thumbInset);
    const uint pxIdx = (pos.y*ctx.thumb.width + pos.x);
    
    const bool selected = (
        imageId>=ctx.selection.first &&
        imageId<ctx.selection.first+ctx.selection.count &&
        selectedImageIds[imageId-ctx.selection.first]
    );
    
    const int maskWidth = maskTxt.get_width();
    const int maskHeight = maskTxt.get_height();
    const int maskWidth2 = maskWidth/2;
    const int maskHeight2 = maskHeight/2;
    const int2 marginX = int2(maskWidth2, (ctx.thumb.width-maskWidth2));
    const int2 marginY = int2(maskHeight2, (ctx.thumb.height-maskHeight2));
    
    const uint32_t pxOff = pxIdx*ctx.thumb.pxSize;
    const float3 thumb = float3(
        ((float)thumbData[pxOff+0] / 255),
        ((float)thumbData[pxOff+1] / 255),
        ((float)thumbData[pxOff+2] / 255)
    );
    
    const bool inThumb = (pos.x>=0 && pos.y>=0 && pos.x<(int)ctx.thumb.width && pos.y<(int)ctx.thumb.height);
    if (!inThumb) return 0;
    return float4(ColorAdjustments(imageOpts, thumb), 1);
    
//    // Calculate mask value
//    float mask = 0;
//    if (inThumb) {
//        if (pos.x<=marginX[0] && pos.y<=marginY[0]) {
//            // Top left
//            mask = Sample::R(maskTxt, int2(pos.x, pos.y));
//        
//        } else if (pos.x>=marginX[1] && pos.y<=marginY[0]) {
//            // Top right
//            mask = Sample::R(maskTxt, int2(maskWidth2+(pos.x-marginX[1]), pos.y));
//        
//        } else if (pos.x<=marginX[0] && pos.y>=marginY[1]) {
//            // Bottom left
//            mask = Sample::R(maskTxt, int2(pos.x, maskHeight2+(pos.y-marginY[1])));
//        
//        } else if (pos.x>=marginX[1] & pos.y>=marginY[1]) {
//            // Bottom right
//            mask = Sample::R(maskTxt, int2(maskWidth2+(pos.x-marginX[1]), maskHeight2+(pos.y-marginY[1])));
//        
//        } else {
//            mask = 1;
//        }
//    }
//    
//    // Calculate outline colors
//    float4 outlineOver = 0;
//    float4 outlineColorDodge = 0;
//    if (inThumb) {
//        int2 outlinePos = pos;
//        if (pos.x <= marginX[0])        outlinePos.x = pos.x;
//        else if (pos.x >= marginX[1])   outlinePos.x = maskWidth2+(pos.x-marginX[1]);
//        else                            outlinePos.x = maskWidth2;
//        
//        if (pos.y <= marginY[0])        outlinePos.y = pos.y;
//        else if (pos.y >= marginY[1])   outlinePos.y = maskHeight2+(pos.y-marginY[1]);
//        else                            outlinePos.y = maskHeight2;
//        
//        const float outline = Sample::R(outlineTxt, outlinePos);
//        
//        if (!selected) {
//            outlineOver = float4(float3(1), .03*outline);
//            outlineColorDodge = float4(float3(.7*outline), 1);
//        
//        } else {
//            outlineOver = float4(float3(1), 0*outline);
//            outlineColorDodge = float4(float3(.5*outline), 1);
//        }
//    }
//    
//    // Calculate shadow value
//    float4 shadow = 0;
//    if (!selected) {
//        const int2 pos = int2(in.posPx);
//        
//        const int shadowWidth = shadowTxt.get_width();
//        const int shadowHeight = shadowTxt.get_height();
//        const int shadowWidth2 = shadowWidth/2;
//        const int shadowHeight2 = shadowHeight/2;
//        const int2 marginX = int2(shadowWidth2, (ctx.cellWidth-shadowWidth2));
//        const int2 marginY = int2(shadowHeight2, (ctx.cellHeight-shadowHeight2));
//        
//        int2 shadowPos = pos;
//        if (pos.x <= marginX[0])        shadowPos.x = pos.x;
//        else if (pos.x >= marginX[1])   shadowPos.x = shadowWidth2+(pos.x-marginX[1]);
//        else                            shadowPos.x = shadowWidth2;
//        
//        if (pos.y <= marginY[0])        shadowPos.y = pos.y;
//        else if (pos.y >= marginY[1])   shadowPos.y = shadowHeight2+(pos.y-marginY[1]);
//        else                            shadowPos.y = shadowHeight2;
//        
//        shadow = float4(0, 0, 0, shadowTxt.sample(coord::pixel, float2(shadowPos.x, shadowPos.y)).a);
//    }
//    
//    // Calculate selection value
//    float4 selection = 0;
//    if (selected) {
//        const int2 pos = int2(in.posPx);
//        
//        const int selectionWidth = selectionTxt.get_width();
//        const int selectionHeight = selectionTxt.get_height();
//        const int selectionWidth2 = selectionWidth/2;
//        const int selectionHeight2 = selectionHeight/2;
//        const int2 marginX = int2(selectionWidth2, (ctx.cellWidth-selectionWidth2));
//        const int2 marginY = int2(selectionHeight2, (ctx.cellHeight-selectionHeight2));
//        
//        int2 selectionPos = pos;
//        if (pos.x <= marginX[0])        selectionPos.x = pos.x;
//        else if (pos.x >= marginX[1])   selectionPos.x = selectionWidth2+(pos.x-marginX[1]);
//        else                            selectionPos.x = selectionWidth2;
//        
//        if (pos.y <= marginY[0])        selectionPos.y = pos.y;
//        else if (pos.y >= marginY[1])   selectionPos.y = selectionHeight2+(pos.y-marginY[1]);
//        else                            selectionPos.y = selectionHeight2;
//        
//        selection = selectionTxt.sample(coord::pixel, float2(selectionPos.x, selectionPos.y));
//    }
//    
//    return
//        blendOver(
//            blendOver(
//                blendMask(mask,
//                blendColorDodge(outlineColorDodge,
//                blendOver(outlineOver, thumb
//            ))), shadow),
//        selection);
}

} // namespace ImageGridLayerShader
} // namespace MDCStudio
