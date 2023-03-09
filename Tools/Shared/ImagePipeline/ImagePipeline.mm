#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "ImagePipeline.h"
#import "ImagePipelineTypes.h"
#import "Defringe.h"
#import "ReconstructHighlights.h"
#import "DebayerLMMSE.h"
#import "LocalContrast.h"
#import "Saturation.h"
#import "EstimateIlluminantFFCC.h"
#import "Tools/Shared/MetalUtil.h"
#import "Tools/Shared/Renderer.h"
#import "Tools/Shared/Mat.h"
using namespace MDCTools;

struct _CCM {
    Color<ColorSpace::Raw> illum;
    Mat<double,3,3> m; // CamRaw -> ProPhotoRGB
};

// Indoor, night
// Calculated from indoor_night2_200.cfa
const _CCM _CCM1 = {
    .illum = { 0.879884, 0.901580, 0.341031 },
    .m = {
        +0.626076, +0.128755, +0.245169,
        -0.396581, +1.438671, -0.042090,
        -0.195309, -0.784350, +1.979659,
    },
};

// Outdoor, 5pm
// Calculated from outdoor_5pm_78.cfa
const _CCM _CCM2 = {
    .illum = { 0.632708, 0.891153, 0.561737 },
    .m = {
        +0.724397, +0.115398, +0.160204,
        -0.238233, +1.361934, -0.123701,
        -0.061917, -0.651388, +1.713306,
    },
};

template <typename T, typename K>
static T _MatrixInterp(const T& lo, const T& hi, K k) {
    return lo*(1-k) + hi*k;
}

static simd::float3 _SimdForMat(const Mat<double,3,1>& m) {
    return {
        simd::float3{(float)m[0], (float)m[1], (float)m[2]},
    };
}

static simd::float3x3 _SimdForMat(const Mat<double,3,3>& m) {
    return {
        simd::float3{(float)m.at(0,0), (float)m.at(1,0), (float)m.at(2,0)},
        simd::float3{(float)m.at(0,1), (float)m.at(1,1), (float)m.at(2,1)},
        simd::float3{(float)m.at(0,2), (float)m.at(1,2), (float)m.at(2,2)},
    };
}

//static _CCM _CCMForIlluminant(const Color<ColorSpace::Raw>& illumRaw) {
//    const simd::float3 a = _SimdForMat(_CCM1.illum.m);
//    const simd::float3 b = _SimdForMat(_CCM2.illum.m);
//    const simd::float3 c = _SimdForMat(illumRaw.m);
//    
//    const simd::float3 ab = (b-a);
//    const simd::float3 ac = (c-a);
//    const simd::float3 ad = simd::project(ac, ab);
//    const simd::float3 pd = a+ad;
//    
//    const float k = simd::length(ad) / simd::length(ab);
//    return {
//        .illum = { pd[0], pd[1], pd[2] },
//        .m = _MatrixInterp(_CCM1.m, _CCM2.m, k),
//    };
//}

namespace MDCTools::ImagePipeline {

Pipeline::ColorMatrix Pipeline::ColorMatrixForIlluminant(const Color<ColorSpace::Raw>& illumRaw) {
    const simd::float3 a = _SimdForMat(_CCM1.illum.m);
    const simd::float3 b = _SimdForMat(_CCM2.illum.m);
    const simd::float3 c = _SimdForMat(illumRaw.m);
    
    const simd::float3 ab = (b-a);
    const simd::float3 ac = (c-a);
    const simd::float3 ad = simd::project(ac, ab);
    
    const float k = simd::length(ad) / simd::length(ab);
    return _MatrixInterp(_CCM1.m, _CCM2.m, k);
}

Pipeline::DebayerResult Pipeline::Debayer(Renderer& renderer, const DebayerOptions& opts, id<MTLTexture> srcRaw, id<MTLTexture> dstRgb) {
    assert(srcRaw);
    assert(dstRgb);
    assert([srcRaw width] == [dstRgb width]);
    assert([srcRaw height] == [dstRgb height]);
    
//    const size_t w = src.width;
//    const size_t h = src.height;
    
    // If an illuminant was provided, use it.
    // Otherwise, estimate it with FFCC.
    Color<ColorSpace::Raw> illum;
    if (opts.illum) {
        illum = *opts.illum;
    } else {
        illum = EstimateIlluminantFFCC::Run(renderer, opts.cfaDesc, srcRaw);
    }
    
    // Reconstruct highlights
    if (opts.reconstructHighlights.en) {
        ReconstructHighlights::Run(renderer, opts.cfaDesc, illum.m, srcRaw);
    }
    
//        // White balance
//        {
//            const double factor = std::max(std::max(illum[0], illum[1]), illum[2]);
//            const Mat<double,3,1> wb(factor/illum[0], factor/illum[1], factor/illum[2]);
//            const simd::float3 simdWB = _SimdForMat(wb);
//            renderer.render(srcRaw,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::WhiteBalance",
//                    // Buffer args
//                    src.cfaDesc,
//                    simdWB,
//                    // Texture args
//                    srcRaw
//                )
//            );
//        }
    
    if (opts.defringe.en) {
        Defringe::Run(renderer, opts.cfaDesc, opts.defringe.opts, srcRaw);
    }
    
    // LMMSE Debayer
    {
        DebayerLMMSE::Run(renderer, opts.cfaDesc, opts.debayerLMMSE.applyGamma, srcRaw, dstRgb);
    }
    
    return Pipeline::DebayerResult{
        .illum = illum,
    };
}

void Pipeline::Process(Renderer& renderer, const ProcessOptions& opts, id<MTLTexture> srcRgb, id<MTLTexture> dstRgb) {
    assert(srcRgb);
    assert(dstRgb);
    
    // White balance
    if (opts.illum) {
        Color<ColorSpace::Raw> illum = *opts.illum;
        const double factor = std::max(std::max(illum[0], illum[1]), illum[2]);
        const Mat<double,3,1> wb(factor/illum[0], factor/illum[1], factor/illum[2]);
        const simd::float3 simdWB = _SimdForMat(wb);
        renderer.render(srcRgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::WhiteBalanceRGB",
                // Buffer args
                simdWB,
                // Texture args
                srcRgb
            )
        );
    }
    
    // Camera raw -> ProPhotoRGB.D50
    if (opts.colorMatrix) {
        const ColorMatrix& colorMatrix = *opts.colorMatrix;
        // If a color matrix was provided, use it.
        // Otherwise estimate it by interpolating between known color matrices.
        renderer.render(srcRgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::ApplyColorMatrix",
                // Buffer args
                _SimdForMat(colorMatrix),
                // Texture args
                srcRgb
            )
        );
    }
    
    // ProPhotoRGB.D50 -> XYZ.D50
    {
        renderer.render(srcRgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYZD50FromProPhotoRGB",
                // Texture args
                srcRgb
            )
        );
    }
    
    // XYZ.D50 -> XYY.D50
    {
        renderer.render(srcRgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYYFromXYZ",
                // Texture args
                srcRgb
            )
        );
    }
    
    // Exposure
    {
        const float exposure = pow(2, opts.exposure);
        renderer.render(srcRgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::Exposure",
                // Buffer args
                exposure,
                // Texture args
                srcRgb
            )
        );
    }
    
    // XYY.D50 -> XYZ.D50
    {
        renderer.render(srcRgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYZFromXYY",
                // Texture args
                srcRgb
            )
        );
    }
    
    // XYZ.D50 -> Lab.D50
    {
        renderer.render(srcRgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::LabD50FromXYZD50",
                // Texture args
                srcRgb
            )
        );
    }
    
    // Brightness
    {
        renderer.render(srcRgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::Brightness",
                // Buffer args
                opts.brightness,
                // Texture args
                srcRgb
            )
        );
    }
    
    // Contrast
    {
        renderer.render(srcRgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::Contrast",
                // Buffer args
                opts.contrast,
                // Texture args
                srcRgb
            )
        );
    }
    
    // Local contrast
    if (opts.localContrast.en) {
        LocalContrast::Run(renderer, opts.localContrast.amount,
            opts.localContrast.radius, srcRgb);
    }
    
    // Lab.D50 -> XYZ.D50
    {
        renderer.render(srcRgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYZD50FromLabD50",
                // Texture args
                srcRgb
            )
        );
    }
    
    // Saturation
    Saturation::Run(renderer, opts.saturation, srcRgb);
    
    // XYZ.D50 -> XYZ.D65
    {
        renderer.render(srcRgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::BradfordXYZD65FromXYZD50",
                // Texture args
                srcRgb
            )
        );
    }
    
    // XYZ.D65 -> LSRGB.D65
    {
        renderer.render(srcRgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::LSRGBD65FromXYZD65",
                // Texture args
                srcRgb
            )
        );
    }
    
    // Copy image from srcRgb -> dstRgb if they're different textures, resizing if needed
    if (srcRgb != dstRgb) {
        const bool resize = ([srcRgb width]!=[dstRgb width] || [srcRgb height]!=[dstRgb height]);
        if (resize) {
            MPSImageLanczosScale* scale = [[MPSImageLanczosScale alloc] initWithDevice:renderer.dev];
            [scale encodeToCommandBuffer:renderer.cmdBuf() sourceTexture:srcRgb destinationTexture:dstRgb];
        
        } else {
            renderer.copy(srcRgb, dstRgb);
        }
    }
}

} // namespace MDCTools::ImagePipeline
