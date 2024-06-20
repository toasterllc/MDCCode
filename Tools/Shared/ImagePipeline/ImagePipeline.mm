#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "ImagePipeline.h"
#import "ImagePipelineTypes.h"
#import "Defringe.h"
#import "ReconstructHighlights.h"
#import "LocalContrast.h"
#import "Saturation.h"
#import "EstimateIlluminant.h"
#import "Code/Lib/LMMSE-Metal/LMMSE.h"
#import "Code/Lib/Toastbox/Mac/MetalUtil.h"
#import "Code/Lib/Toastbox/Mac/Renderer.h"
#import "Code/Lib/Toastbox/Mac/Mat.h"
using namespace Toastbox;

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

namespace ImagePipeline {

//Color<ColorSpace::Raw> Pipeline::EstimateIlluminant(Renderer& renderer, const CFADesc& cfaDesc, id<MTLTexture> srcRaw) {
//    return EstimateIlluminant::Run(renderer, cfaDesc, srcRaw);
//}
//
//void Pipeline::Debayer(Renderer& renderer, const DebayerOptions& opts, id<MTLTexture> srcRaw, id<MTLTexture> dstRgb) {
//    assert(srcRaw);
//    assert(dstRgb);
//    assert([srcRaw width] == [dstRgb width]);
//    assert([srcRaw height] == [dstRgb height]);
//    
//    // Reconstruct highlights
//    if (opts.reconstructHighlights.en) {
//        ReconstructHighlights::Run(renderer, opts.cfaDesc, opts.illum.m, srcRaw);
//    }
//    
//    if (opts.defringe.en) {
//        Defringe::Run(renderer, opts.cfaDesc, opts.defringe.opts, srcRaw);
//    }
//    
//    // LMMSE Debayer
//    {
//        DebayerLMMSE::Run(renderer, opts.cfaDesc, opts.debayerLMMSE.applyGamma, srcRaw, dstRgb);
//    }
//}

static Renderer::Txt _TimestampTextureCreate(Renderer& renderer, std::string_view str) {
    static constexpr MTLPixelFormat _PixelFormat = MTLPixelFormatRGBA8Unorm;
    
    NSAttributedString* astr = [[NSAttributedString alloc] initWithString:@(std::string(str).c_str())
    attributes:@{
        NSFontAttributeName: [NSFont fontWithName:@"Helvetica Neue Light" size:48],
        NSForegroundColorAttributeName: [NSColor whiteColor],
    }];
    
    constexpr CGFloat PaddingX = 20;
    constexpr CGFloat PaddingY = 2;
    constexpr size_t SamplesPerPixel = 4;
    constexpr size_t BytesPerSample = 1;
    const CGSize astrSize = [astr size];
    const size_t w = std::lround(astrSize.width+2*PaddingX);
    const size_t h = std::lround(astrSize.height+2*PaddingY);
    const size_t bytesPerRow = SamplesPerPixel*BytesPerSample*w;
    id /* CGColorSpaceRef */ cs = CFBridgingRelease(CGColorSpaceCreateWithName(kCGColorSpaceSRGB));
    const id /* CGContextRef */ ctx = CFBridgingRelease(CGBitmapContextCreate(nullptr, w, h, BytesPerSample*8,
        bytesPerRow, (CGColorSpaceRef)cs, kCGImageAlphaPremultipliedLast));
    
    const CGRect bounds = {{}, { (CGFloat)w, (CGFloat)h }};
//    CGContextScaleCTM((CGContextRef)ctx, contentsScale, contentsScale);
    CGContextSetRGBFillColor((CGContextRef)ctx, 0, 0, 0, 1);
    CGContextFillRect((CGContextRef)ctx, bounds);
    
    NSGraphicsContext* nsctx = [NSGraphicsContext graphicsContextWithCGContext:(CGContextRef)ctx flipped:false];
    [NSGraphicsContext setCurrentContext:nsctx];
    [astr drawAtPoint:{ PaddingX, PaddingY }];
    
    const uint8_t* samples = (const uint8_t*)CGBitmapContextGetData((CGContextRef)ctx);
    Renderer::Txt txt = renderer.textureCreate(_PixelFormat, w, h);
    renderer.textureWrite(txt, samples, SamplesPerPixel);
    return txt;
}

static simd::float2 _TimestampOffset(simd::float2 position, simd::float2 size) {
    return simd::float2{ 1.f-size.x, 1.f-size.y } * position;
}

void Pipeline::Run(Renderer& renderer, const Options& opts, id<MTLTexture> srcRaw, id<MTLTexture> dstRgb) {
    assert(srcRaw);
    assert(dstRgb);
    
    // Reconstruct highlights
    if (opts.reconstructHighlights.en) {
        assert(opts.illum);
        ReconstructHighlights::Run(renderer, opts.cfaDesc, opts.illum->m, srcRaw);
    }
    
    // Defringe (currently unused)
    if (opts.defringe.en) {
        Defringe::Run(renderer, opts.cfaDesc, opts.defringe.opts, srcRaw);
    }
    
    // Debayer (LMMSE)
    Renderer::Txt srcRgb = renderer.textureCreate(srcRaw, MTLPixelFormatRGBA32Float);
    {
        LMMSE::Run(renderer, opts.cfaDesc, opts.debayerLMMSE.applyGamma, srcRaw, srcRgb);
    }
    
    // White balance
    if (opts.illum) {
        Color<ColorSpace::Raw> illum = *opts.illum;
        const double factor = std::max(std::max(illum[0], illum[1]), illum[2]);
        printf("ILLUM: %f %f %f\n", illum[0], illum[1], illum[2]);
        
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
    
    // Color correction (Camera raw -> XYZ.D50)
    if (opts.colorMatrix) {
        const ColorMatrix& colorMatrix = *opts.colorMatrix;
        printf("Color matrix:\n");
        colorMatrix.inv().print();
        colorMatrix.print();
        printf("\n\n\n");
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
        constexpr float ExposureCoeff = 4;
        const float exposure = pow(2, ExposureCoeff*opts.exposure);
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
    if (opts.localContrast.amount != 0) {
        LocalContrast::Run(renderer, opts.localContrast.amount, opts.localContrast.radius, srcRgb);
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
    {
        constexpr float SaturationCoeff = 2;
        Saturation::Run(renderer, SaturationCoeff*opts.saturation, srcRgb);
    }
    
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
    
//    // XYZ.D65 -> P3Display.D65
//    {
//        renderer.render(srcRgb,
//            renderer.FragmentShader(ImagePipelineShaderNamespace "Base::P3DisplayD65FromFromXYZD65",
//                // Texture args
//                srcRgb
//            )
//        );
//    }
    
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
    
    // Draw the timestamp string if requested
    if (!opts.timestamp.string.empty()) {
        TimestampOverlayRender(renderer, opts.timestamp, dstRgb);
    }
}

void Pipeline::TimestampOverlayRender(Toastbox::Renderer& renderer,
    const Pipeline::TimestampOptions& opts, id<MTLTexture> txt) {
    
    assert(!opts.string.empty());
    Renderer::Txt timestampTxt = _TimestampTextureCreate(renderer, opts.string);
    
    const simd::float2 timestampSize = {
        (float)[timestampTxt width] / [txt width],
        (float)[timestampTxt height] / [txt height],
    };
    
    const simd::float2 timestampOffset = _TimestampOffset(opts.position, timestampSize);
    
    const TimestampContext ctx = {
        .timestampOffset = timestampOffset,
        .timestampSize   = timestampSize,
    };
    
    // Render the timestamp if requested
    renderer.render(txt, Renderer::BlendType::None,
        renderer.VertexShader(ImagePipelineShaderNamespace "Base::TimestampVertexShader", ctx),
        renderer.FragmentShader(ImagePipelineShaderNamespace "Base::TimestampFragmentShader", timestampTxt)
    );
}

} // namespace ImagePipeline
