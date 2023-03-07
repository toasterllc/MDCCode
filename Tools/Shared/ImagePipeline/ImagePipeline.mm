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

static _CCM _CCMForIlluminant(const Color<ColorSpace::Raw>& illumRaw) {
    const simd::float3 a = _SimdForMat(_CCM1.illum.m);
    const simd::float3 b = _SimdForMat(_CCM2.illum.m);
    const simd::float3 c = _SimdForMat(illumRaw.m);
    
    const simd::float3 ab = (b-a);
    const simd::float3 ac = (c-a);
    const simd::float3 ad = simd::project(ac, ab);
    const simd::float3 pd = a+ad;
    
    const float k = simd::length(ad) / simd::length(ab);
    return {
        .illum = { pd[0], pd[1], pd[2] },
        .m = _MatrixInterp(_CCM1.m, _CCM2.m, k),
    };
}

namespace MDCTools::ImagePipeline {

Pipeline::Result Pipeline::Run(MDCTools::Renderer& renderer, const Options& opts, const RawImage& src, id<MTLTexture> dst) {
    assert(src.width);
    assert(src.height);
    assert(src.pixels);
    assert(dst);
    
    constexpr uint32_t DownsampleFactor = 1;
    const size_t w = src.width/DownsampleFactor;
    const size_t h = src.height/DownsampleFactor;
    
    Renderer::Txt raw = renderer.textureCreate(MTLPixelFormatR32Float, w, h);
    
    // Load `raw`
    {
        constexpr size_t SamplesPerPixel = 1;
        constexpr size_t BytesPerSample = sizeof(*src.pixels);
        renderer.textureWrite(raw, src.pixels, SamplesPerPixel, BytesPerSample, ImagePixelMax);
    }
    
    Renderer::Txt rgb = renderer.textureCreate(MTLPixelFormatRGBA32Float, w, h);
    Color<ColorSpace::Raw> illum;
    Mat<double,3,3> colorMatrix;
    
//        renderer.debugShowTexture(raw);
    
    // If an illuminant was provided, use it.
    // Otherwise, estimate it with FFCC.
    if (opts.illum) {
        illum = *opts.illum;
    } else {
        illum = EstimateIlluminantFFCC::Run(renderer, src.cfaDesc, raw);
    }
    
    // Reconstruct highlights
    if (opts.reconstructHighlights.en) {
        ReconstructHighlights::Run(renderer, src.cfaDesc, illum.m, raw);
    }
    
//        // White balance
//        {
//            const double factor = std::max(std::max(illum[0], illum[1]), illum[2]);
//            const Mat<double,3,1> wb(factor/illum[0], factor/illum[1], factor/illum[2]);
//            const simd::float3 simdWB = _SimdForMat(wb);
//            renderer.render(raw,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::WhiteBalance",
//                    // Buffer args
//                    src.cfaDesc,
//                    simdWB,
//                    // Texture args
//                    raw
//                )
//            );
//        }
    
    if (opts.defringe.en) {
        Defringe::Run(renderer, src.cfaDesc, opts.defringe.opts, raw);
    }
    
    // LMMSE Debayer
    {
        DebayerLMMSE::Run(renderer, src.cfaDesc, opts.debayerLMMSE.applyGamma, raw, rgb);
    }
    
    
    
    
    
    
    
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
//        // Local contrast
//        if (opts.localContrast.en) {
//            LocalContrast::Run(renderer, opts.localContrast.amount,
//                opts.localContrast.radius, rgb);
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
//        // XYZ.D50 -> ProPhotoRGB
//        {
//            renderer.render(rgb,
//                renderer.FragmentShader(ImagePipelineShaderNamespace "Base::ProPhotoRGBFromXYZD50",
//                    // Texture args
//                    rgb
//                )
//            );
//        }
    
    
    
    
    
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
//        // Local contrast
//        if (opts.localContrast.en) {
//            LocalContrast::Run(renderer, opts.localContrast.amount,
//                opts.localContrast.radius, rgb);
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
    
    
    
    
    
    // White balance
    {
        const double factor = std::max(std::max(illum[0], illum[1]), illum[2]);
        const Mat<double,3,1> wb(factor/illum[0], factor/illum[1], factor/illum[2]);
        const simd::float3 simdWB = _SimdForMat(wb);
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::WhiteBalanceRGB",
                // Buffer args
                simdWB,
                // Texture args
                rgb
            )
        );
    }
    
    
    // Camera raw -> ProPhotoRGB
    {
        // If a color matrix was provided, use it.
        // Otherwise estimate it by interpolating between known color matrices.
        colorMatrix = (opts.colorMatrix ? *opts.colorMatrix : _CCMForIlluminant(illum).m);
        
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::ApplyColorMatrix",
                // Buffer args
                _SimdForMat(colorMatrix),
                // Texture args
                rgb
            )
        );
    }
    
    // ProPhotoRGB -> XYZ.D50
    {
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYZD50FromProPhotoRGB",
                // Texture args
                rgb
            )
        );
    }
    
    // XYZ.D50 -> XYY.D50
    {
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYYFromXYZ",
                // Texture args
                rgb
            )
        );
    }
    
    // Exposure
    {
        const float exposure = pow(2, opts.exposure);
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::Exposure",
                // Buffer args
                exposure,
                // Texture args
                rgb
            )
        );
    }
    
    // XYY.D50 -> XYZ.D50
    {
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYZFromXYY",
                // Texture args
                rgb
            )
        );
    }
    
    // XYZ.D50 -> Lab.D50
    {
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::LabD50FromXYZD50",
                // Texture args
                rgb
            )
        );
    }
    
    // Brightness
    {
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::Brightness",
                // Buffer args
                opts.brightness,
                // Texture args
                rgb
            )
        );
    }
    
    // Contrast
    {
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::Contrast",
                // Buffer args
                opts.contrast,
                // Texture args
                rgb
            )
        );
    }
    
    // Local contrast
    if (opts.localContrast.en) {
        LocalContrast::Run(renderer, opts.localContrast.amount,
            opts.localContrast.radius, rgb);
    }
    
    // Lab.D50 -> XYZ.D50
    {
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::XYZD50FromLabD50",
                // Texture args
                rgb
            )
        );
    }
    
    // Saturation
    Saturation::Run(renderer, opts.saturation, rgb);
    
    // XYZ.D50 -> XYZ.D65
    {
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::BradfordXYZD65FromXYZD50",
                // Texture args
                rgb
            )
        );
    }
    
    // XYZ.D65 -> LSRGB.D65
    {
        renderer.render(rgb,
            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::LSRGBD65FromXYZD65",
                // Texture args
                rgb
            )
        );
    }
    
    // Copy image from rgb -> dst, resizing if needed
    const bool resize = (src.width!=[dst width] || src.height!=[dst height]);
    if (resize) {
        MPSImageLanczosScale* scale = [[MPSImageLanczosScale alloc] initWithDevice:renderer.dev];
        [scale encodeToCommandBuffer:renderer.cmdBuf() sourceTexture:rgb destinationTexture:dst];
    
    } else {
        renderer.copy(rgb, dst);
    }
    
    
    
    // We changed our semantics to explicitly output LSRGB, so we no longer apply the SRGB gamma ourselves
//        // Apply SRGB gamma
//        {
//            renderer.render(rgb, ImagePipelineShaderNamespace "Base::SRGBGamma",
//                // Texture args
//                rgb
//            );
//        }
    
    return Result{
        .illum = illum,
        .colorMatrix = colorMatrix,
    };
}

} // namespace MDCTools::ImagePipeline
