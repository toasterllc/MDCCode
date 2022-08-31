#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "ImagePipeline.h"
#import "Tools/Shared/MetalUtil.h"
#import "Tools/Shared/Renderer.h"
#import "ImagePipelineTypes.h"
#import "Defringe.h"
#import "ReconstructHighlights.h"
#import "DebayerLMMSE.h"
#import "LocalContrast.h"
#import "Saturation.h"
#import "Tools/Shared/Mat.h"
#import "EstimateIlluminantFFCC.h"
#import "ImageLibrary.h"
using namespace MDCTools;

struct CCM {
    double cct = 0;
    Mat<double,3,3> m; // CamRaw -> ProPhotoRGB
};

// Indoor, night
// Calculated from indoor_night2_200.cfa (by averaging the result with the identity matrix)
const CCM CCM1 = {
    .cct = 3400, // Guess for indoor lighting
    .m = {
        0.809537000000000,  0.067678500000000,  0.122785000000000,
        -0.196449000000000, 1.221760000000000,  -0.025311000000000,
        -0.091125500000000, -0.363321500000000, 1.454447000000000,
    },
};

// Outdoor, 5pm
// Calculated from outdoor_5pm_74.cfa (by averaging the result with the identity matrix)
const CCM CCM2 = {
    .cct = 6504,    // D65, guesstimated to find a value such that most images' illuminants
                    // aren't capped at 6504 (via the CCMForIlluminant algorithm)
    .m = {
        0.856270500000000,  0.063702500000000,  0.080027000000000,
        -0.190480000000000, 1.265983000000000,  -0.075503000000000,
        -0.082371000000000, -0.180686000000000, 1.263057000000000,
    },
};

static Mat<double,3,3> CCMInterp(const CCM& lo, const CCM& hi, double cct) {
    const double k = ((1/cct) - (1/lo.cct)) / ((1/hi.cct) - (1/lo.cct));
    return lo.m*(1-k) + hi.m*k;
}

// Approximate CCT given xy chromaticity, using the Hernandez-Andres equation
static double CCTForXYChromaticity(double x, double y) {
    const double xe[]   = { 0.3366,      0.3356     };
    const double ye[]   = { 0.1735,      0.1691     };
    const double A0[]   = { -949.86315,  36284.48953};
    const double A1[]   = { 6253.80338,  0.00228    };
    const double t1[]   = { 0.92159,     0.07861    };
    const double A2[]   = { 28.70599,    5.4535e-36 };
    const double t2[]   = { 0.20039,     0.01543    };
    const double A3[]   = { 0.00004,     0          };
    const double t3[]   = { 0.07125,     0.07125    };
    const double n[]    = {(x-xe[0])/(y-ye[0]), (x-xe[1])/(y-ye[1])};
    const double cct[]  = {
        A0[0] + A1[0]*exp(-n[0]/t1[0]) + A2[0]*exp(-n[0]/t2[0]) + A3[0]*exp(-n[0]/t3[0]),
        A0[1] + A1[1]*exp(-n[1]/t1[1]) + A2[1]*exp(-n[1]/t2[1]) + A3[1]*exp(-n[1]/t3[1]),
    };
    
    if (cct[0] <= 50000) return cct[0];
    else                 return cct[1];
}

static CCM CCMForIlluminant(const Color<ColorSpace::Raw>& illumRaw) {
    // Start out with a guess for the xy coordinates (D55 chromaticity)
    double x = 0.332424;
    double y = 0.347426;
    CCM ccm;
    
    // Iteratively estimate the xy chromaticity of `illumRaw`,
    // along with the CCT and interpolated CCM.
    constexpr int MaxIter = 50;
    for (int i=0; i<MaxIter; i++) {
        // Calculate CCT from current xy chromaticity estimate, and interpolate between
        // CCM1 and CCM2 based on that CCT
        CCM ccm2;
        ccm2.cct = std::clamp(CCTForXYChromaticity(x,y), CCM1.cct, CCM2.cct);
        ccm2.m = CCMInterp(CCM1, CCM2, ccm2.cct);
        
        // Convert `illumRaw` to ProPhotoRGB coordinates using ccm2 (the new interpolated CCM)
        const Color<ColorSpace::ProPhotoRGB> illumRGB(ccm2.m * illumRaw.m);
        // Convert illumRGB to XYZ coordinates
        const Color<ColorSpace::XYZ<ColorSpace::ProPhotoRGB::White>> illumXYZ(illumRGB);
        
        constexpr double Eps = .01;
        const double x2 = illumXYZ[0]/(illumXYZ[0]+illumXYZ[1]+illumXYZ[2]);
        const double y2 = illumXYZ[1]/(illumXYZ[0]+illumXYZ[1]+illumXYZ[2]);
        const double Δx = std::abs((x-x2)/x);
        const double Δy = std::abs((y-y2)/y);
        const double Δcct = std::abs((ccm.cct-ccm2.cct)/ccm.cct);
        double Δccm = 0;
        for (int y=0; y<3; y++) {
            for (int x=0; x<3; x++) {
                Δccm = std::max(Δccm, std::abs((ccm.m.at(y,x)-ccm2.m.at(y,x))/ccm.m.at(y,x)));
            }
        }
        
        ccm = ccm2;
        x = x2;
        y = y2;
        
        if (Δx<Eps && Δy<Eps && Δcct<Eps && Δccm<Eps) return ccm;
    }
    
    throw std::runtime_error("didn't converge");
}


static simd::float3 simdForMat(const Mat<double,3,1>& m) {
    return {
        simd::float3{(float)m[0], (float)m[1], (float)m[2]},
    };
}

static simd::float3x3 simdForMat(const Mat<double,3,3>& m) {
    return {
        simd::float3{(float)m.at(0,0), (float)m.at(1,0), (float)m.at(2,0)},
        simd::float3{(float)m.at(0,1), (float)m.at(1,1), (float)m.at(2,1)},
        simd::float3{(float)m.at(0,2), (float)m.at(1,2), (float)m.at(2,2)},
    };
}

namespace MDCStudio::ImagePipeline {

Pipeline::Result Pipeline::Run(MDCTools::Renderer& renderer, const RawImage& rawImg, const Options& opts) {
    const size_t wraw = rawImg.width;
    const size_t hraw = rawImg.height;
    
    constexpr uint32_t DownsampleFactor = 4;
    const size_t w = wraw/DownsampleFactor;
    const size_t h = hraw/DownsampleFactor;
    
    Renderer::Txt raw = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
    
    {
        Renderer::Txt rawLarge = renderer.textureCreate(MTLPixelFormatR32Float, wraw, hraw);
        
        // Load `rawLarge`
        {
            constexpr size_t SamplesPerPixel = 1;
            constexpr size_t BytesPerSample = sizeof(*rawImg.pixels);
            renderer.textureWrite(rawLarge, rawImg.pixels, SamplesPerPixel, BytesPerSample, ImagePixelMax);
        }
        
        {
            renderer.render(raw,
                renderer.FragmentShader(ImagePipelineShaderNamespace "DownsampleLoad",
                    // Buffer args,
                    DownsampleFactor,
                    // Texture args
                    rawLarge
                )
            );
        }
    }
    
    Renderer::Txt rgbTmp1 = renderer.textureCreate(MTLPixelFormatRGBA32Float, [raw width], [raw height], MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget);
    
    Renderer::Txt rgb = renderer.textureCreate(MTLPixelFormatRGBA32Float,
        MDCStudio::ImageThumb::ThumbWidth,
        MDCStudio::ImageThumb::ThumbHeight,
        MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget
    );
    Color<ColorSpace::Raw> illumEst;
    
    // Raw mode (bilinear debayer only)
    {
        // De-bayer
        renderer.render(rgbTmp1,
            renderer.FragmentShader(ImagePipelineShaderNamespace "DebayerBilinear::Debayer",
                // Buffer args
                rawImg.cfaDesc,
                // Texture args
                raw
            )
        );
        
//        auto rgbTmp2 = renderer.copy(rgbTmp1);
//        MPSImageGaussianBlur* blur = [[MPSImageGaussianBlur alloc] initWithDevice:renderer.dev sigma:.1];
//        [blur encodeToCommandBuffer:renderer.cmdBuf() sourceTexture:rgbTmp2 destinationTexture:rgbTmp1];
    }
    
//    // LMMSE debayer mode
//    {
//        // Estimate illuminant, if an illuminant isn't provided in `opts.illum`
//        Color<ColorSpace::Raw> illum = {1,1,1};
////        if (opts.illum) {
////            illum = *opts.illum;
////        } else {
////            illum = EstimateIlluminantFFCC::Run(renderer, rawImg.cfaDesc, raw);
////            illumEst = illum;
////        }
////        
////        // Reconstruct highlights
////        if (opts.reconstructHighlights.en) {
////            ReconstructHighlights::Run(renderer, rawImg.cfaDesc, illum.m, raw);
////        }
////        
////        // LMMSE Debayer
////        {
//            DebayerLMMSE::Run(renderer, rawImg.cfaDesc, opts.debayerLMMSE.applyGamma, raw, rgbTmp1);
////        }
//    }
    
    MPSImageLanczosScale* resample = [[MPSImageLanczosScale alloc] initWithDevice:renderer.dev];
    [resample encodeToCommandBuffer:renderer.cmdBuf() sourceTexture:rgbTmp1 destinationTexture:rgb];
    
    return Result{
        .txt = std::move(rgb),
        .illumEst = illumEst,
    };
}

} // namespace MDCStudio::ImagePipeline
