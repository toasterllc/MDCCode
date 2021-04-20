#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "ImagePipeline.h"
#import "MetalUtil.h"
#import "Renderer.h"
#import "ImagePipelineTypes.h"
#import "Defringe.h"
#import "ReconstructHighlights.h"
#import "DebayerLMMSE.h"
#import "LocalContrast.h"
#import "Saturation.h"
#import "Mat.h"
#import "EstimateIlluminantFFCC.h"

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

namespace CFAViewer::ImagePipeline {

void Pipeline::Run(
    Renderer& renderer,
    const Image& img,
    const Options& opts,
    const SampleOptions& sampleOpts,
    id<MTLTexture> outTxt
) {
    const uint32_t w = img.width;
    const uint32_t h = img.height;
    
    Renderer::Txt raw = renderer.textureCreate(MTLPixelFormatR32Float,
        img.width, img.height);
    
    // Load `raw`
    {
        const size_t samplesPerPixel = 1;
        const size_t bytesPerSample = sizeof(MetalUtil::ImagePixel);
        renderer.textureWrite(raw, img.pixels, samplesPerPixel, bytesPerSample, MetalUtil::ImagePixelMax);
    }
    
    // Sample: fill `sampleOpts.raw`
    {
        renderer.render("CFAViewer::Shader::ImagePipeline::SampleRaw",
            w, h,
            // Buffer args
            img.cfaDesc,
            sampleOpts.rect,
            sampleOpts.raw,
            // Texture args
            raw
        );
    }
    
    Renderer::Txt rgb = renderer.textureCreate(MTLPixelFormatRGBA32Float,
        img.width, img.height);
    
    // Raw mode (bilinear debayer only)
    if (opts.rawMode) {
        // De-bayer
        renderer.render("CFAViewer::Shader::DebayerBilinear::Debayer", rgb,
            // Buffer args
            img.cfaDesc,
            // Texture args
            raw
        );
    
    } else {
        // Estimate illuminant
        const Color<ColorSpace::Raw> illum = EstimateIlluminantFFCC::Run(renderer, img.cfaDesc, raw);
        
        // Reconstruct highlights
        if (opts.reconstructHighlights.en) {
            ReconstructHighlights::Run(renderer, img.cfaDesc, illum.m, raw);
        }
        
        // Sample: fill `sampleOpts.xyzD50`
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::SampleRaw",
                w, h,
                // Buffer args
                img.cfaDesc,
                sampleOpts.rect,
                sampleOpts.xyzD50,
                // Texture args
                raw
            );
        }
        
        // White balance
        {
            const double factor = std::max(std::max(illum[0], illum[1]), illum[2]);
            const Mat<double,3,1> wb(factor/illum[0], factor/illum[1], factor/illum[2]);
            const simd::float3 simdWB = simdForMat(wb);
            renderer.render("CFAViewer::Shader::ImagePipeline::WhiteBalance", raw,
                // Buffer args
                img.cfaDesc,
                simdWB,
                // Texture args
                raw
            );
        }
        
        if (opts.defringe.en) {
            Defringe::Run(renderer, img.cfaDesc, opts.defringe.opts, raw);
        }
        
        // LMMSE Debayer
        {
            DebayerLMMSE::Run(renderer, img.cfaDesc, opts.debayerLMMSE.applyGamma, raw, rgb);
        }
        
        // Camera raw -> ProPhotoRGB
        {
            const simd::float3x3 colorMatrix = simdForMat(opts.colorMatrix);
            renderer.render("CFAViewer::Shader::ImagePipeline::ApplyColorMatrix", rgb,
                // Buffer args
                colorMatrix,
                // Texture args
                rgb
            );
        }
        
        // ProPhotoRGB -> XYZ.D50
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::XYZD50FromProPhotoRGB", rgb,
                // Texture args
                rgb
            );
        }
        
        // XYZ.D50 -> XYY.D50
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::XYYFromXYZ", rgb,
                // Texture args
                rgb
            );
        }
        
        // Exposure
        {
            const float exposure = pow(2, opts.exposure);
            renderer.render("CFAViewer::Shader::ImagePipeline::Exposure", rgb,
                // Buffer args
                exposure,
                // Texture args
                rgb
            );
        }
        
        // XYY.D50 -> XYZ.D50
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::XYZFromXYY", rgb,
                // Texture args
                rgb
            );
        }
        
        // XYZ.D50 -> Lab.D50
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::LabD50FromXYZD50", rgb,
                // Texture args
                rgb
            );
        }
        
        // Brightness
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::Brightness", rgb,
                // Buffer args
                opts.brightness,
                // Texture args
                rgb
            );
        }
        
        // Contrast
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::Contrast", rgb,
                // Buffer args
                opts.contrast,
                // Texture args
                rgb
            );
        }
        
        // Local contrast
        if (opts.localContrast.en) {
            LocalContrast::Run(renderer, opts.localContrast.amount,
                opts.localContrast.radius, rgb);
        }
        
        // Lab.D50 -> XYZ.D50
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::XYZD50FromLabD50", rgb,
                // Texture args
                rgb
            );
        }
        
        // Saturation
        Saturation::Run(renderer, opts.saturation, rgb);
        
//            // Sample: fill `sampleOpts.xyzD50`
//            {
//                renderer.render("CFAViewer::Shader::ImagePipeline::SampleRGB",
//                    w, h,
//                    // Buffer args
//                    img.cfaDesc,
//                    sampleOpts.rect,
//                    sampleOpts.xyzD50,
//                    // Texture args
//                    rgb
//                );
//            }
        
        // XYZ.D50 -> XYZ.D65
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::BradfordXYZD65FromXYZD50", rgb,
                // Texture args
                rgb
            );
        }
        
        // XYZ.D65 -> LSRGB.D65
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::LSRGBD65FromXYZD65", rgb,
                // Texture args
                rgb
            );
        }
        
        // Apply SRGB gamma
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::SRGBGamma", rgb,
                // Texture args
                rgb
            );
        }
        
        // Sample: fill `sampleOpts.srgb`
        {
            renderer.render("CFAViewer::Shader::ImagePipeline::SampleRGB",
                w, h,
                // Buffer args
                img.cfaDesc,
                sampleOpts.rect,
                sampleOpts.srgb,
                // Texture args
                rgb
            );
        }
    }
    
    // Final display render pass (which converts the RGBA32Float -> BGRA8Unorm)
    renderer.render("CFAViewer::Shader::ImagePipeline::Display", outTxt,
        // Texture args
        rgb
    );
}

} // namespace CFAViewer::ImagePipeline
