#import <Cocoa/Cocoa.h>
#import <sys/stat.h>
#import <vector>
#import <string>
#import <filesystem>
#import <iostream>
#import <unordered_map>
#import "Toastbox/Mmap.h"
#import "Tools/Shared/Renderer.h"
#import "Tools/Shared/Mat.h"
#import "Tools/Shared/Color.h"
#import "Tools/Shared/CFA.h"
#import "Tools/Shared/ImagePipeline/ImagePipelineTypes.h"
#import "Tools/Shared/ImagePipeline/DebayerLMMSE.h"
using namespace MDCTools;
namespace fs = std::filesystem;

struct CCM {
    double cct = 0;
    Mat<double,3,3> m; // CamRaw -> ProPhotoRGB
};

// Indoor, night
const CCM CCM1 = {
    .cct = 2700, // Guess for indoor lighting
    .m = {
        0.809537000000000,  0.067678500000000,  0.122785000000000,
        -0.196449000000000, 1.221760000000000,  -0.025311000000000,
        -0.091125500000000, -0.363321500000000, 1.454447000000000,
    },
};

// Outdoor, 4pm
const CCM CCM2 = {
    .cct = 5503, // D55 (afternoon daylight)
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

static simd::float3x3 SIMDFromMat(const Mat<double,3,3>& m) {
    return {
        simd::float3{(float)m.at(0,0), (float)m.at(1,0), (float)m.at(2,0)},
        simd::float3{(float)m.at(0,1), (float)m.at(1,1), (float)m.at(2,1)},
        simd::float3{(float)m.at(0,2), (float)m.at(1,2), (float)m.at(2,2)},
    };
}

static void writePNG(Renderer& renderer, id<MTLTexture> txt, const fs::path& path) {
    id img = renderer.imageCreate(txt);
    if (!img) throw std::runtime_error("renderer.createCGImage returned nil");
    
    id imgDest = CFBridgingRelease(CGImageDestinationCreateWithURL(
        (CFURLRef)[NSURL fileURLWithPath:@(path.c_str())], kUTTypePNG, 1, nullptr));
    if (!imgDest) throw std::runtime_error("CGImageDestinationCreateWithURL returned nil");
    CGImageDestinationAddImage((CGImageDestinationRef)imgDest, (CGImageRef)img, nullptr);
    CGImageDestinationFinalize((CGImageDestinationRef)imgDest);
}

static void createPNGFromCFA(Renderer& renderer, uint32_t width, uint32_t height, const fs::path& path) {
    using namespace ImagePipeline;
    const CFADesc CFADesc = {CFAColor::Green, CFAColor::Red, CFAColor::Blue, CFAColor::Green};
    
//    const Mat<double,3,3> C5IllumCorrectionMatrix(
//        1.25407726323103,       0., -0.245441000321451,
//        0.,                     1., 0.,
//        -0.0687922873207393,    0., 0.868851550191642
//    );
    
//    const std::unordered_map<std::string,Color<ColorSpace::Raw>> C50Illuminants = {
//    #include "IllumsC5.h"
//    };
//    const Color<ColorSpace::Raw>& illum = C50Illuminants.at(path.filename().replace_extension());
//    const Color<ColorSpace::Raw>& illumRaw = C50Illuminants.at(path.filename().replace_extension());
//    const Color<ColorSpace::Raw>& illum(C5IllumCorrectionMatrix*illumRaw.m);
    const size_t len = sizeof(uint16_t)*width*height;
    const Toastbox::Mmap imgMmap(path.c_str());
    
    // Verify that the file size is what we expect, given the image width/height
    if (imgMmap.len() != len) throw std::runtime_error("invalid length");
    
    // Create a texture from the raw CFA data
    Renderer::Txt raw = renderer.textureCreate(MTLPixelFormatR32Float, width, height);
    renderer.textureWrite(raw, (uint16_t*)imgMmap.data(), 1, sizeof(uint16_t), ImagePixelMax);
    
//    // Reconstruct highlights
//    {
//        const simd::float3 badPixelFactors = {1.130, 1.613, 1.000};
//        const simd::float3 goodPixelFactors = {1.051, 1.544, 1.195};
//        Renderer::Txt tmp = renderer.textureCreate(MTLPixelFormatR32Float, width, height);
//        renderer.render("CFAViewer::Shader::ImagePipeline::ReconstructHighlights", tmp,
//            // Buffer args
//            CFADesc,
//            badPixelFactors,
//            goodPixelFactors,
//            // Texture args
//            raw
//        );
//        raw = std::move(tmp);
//    }
//    
//    // White balance
//    {
//        const simd::float3 whiteBalance = {
//            (float)(illum[1]/illum[0]),
//            (float)(illum[1]/illum[1]),
//            (float)(illum[1]/illum[2])
//        };
//        renderer.render("CFAViewer::Shader::ImagePipeline::WhiteBalance", raw,
//            // Buffer args
//            CFADesc,
//            whiteBalance,
//            // Texture args
//            raw
//        );
//    }
    
    const uint32_t scaledWidth = 384;
    const uint32_t scaledHeight = (uint32_t)((scaledWidth*[raw height])/[raw width]);
    Renderer::Txt rgb = renderer.textureCreate(MTLPixelFormatRGBA32Float, scaledWidth, scaledHeight);
    
    renderer.render(rgb,
        renderer.FragmentShader(ImagePipelineShaderNamespace "Base::DebayerDownsample",
            // Buffer args
            CFADesc,
            // Texture args
            raw,
            rgb
        )
    );
    
//    // LMMSE Debayer
//    Renderer::Txt rgb = renderer.textureCreate(MTLPixelFormatRGBA32Float, width, height);
//    {
//        DebayerLMMSE::Run(renderer, CFADesc, false, raw, rgb);
//    }
    
//    // Camera raw -> ProPhotoRGB
//    {
//        const CCM ccm = CCMForIlluminant(illum);
//        const simd::float3x3 ccmSIMD = SIMDFromMat(ccm.m);
//        renderer.render("CFAViewer::Shader::ImagePipeline::ApplyColorMatrix", rgb,
//            // Buffer args
//            ccmSIMD,
//            // Texture args
//            rgb
//        );
//    }
//    
//    // ProPhotoRGB -> XYZ.D50
//    {
//        renderer.render("CFAViewer::Shader::ImagePipeline::XYZD50FromProPhotoRGB", rgb,
//            // Texture args
//            rgb
//        );
//    }
//    
//    // XYZ.D50 -> XYZ.D65
//    {
//        renderer.render("CFAViewer::Shader::ImagePipeline::BradfordXYZD65FromXYZD50", rgb,
//            // Texture args
//            rgb
//        );
//    }
//    
//    // XYZ.D65 -> LSRGB.D65
//    {
//        renderer.render("CFAViewer::Shader::ImagePipeline::LSRGBD65FromXYZD65", rgb,
//            // Texture args
//            rgb
//        );
//    }
//    
//    // Apply SRGB gamma
//    {
//        renderer.render("CFAViewer::Shader::ImagePipeline::SRGBGamma", rgb,
//            // Texture args
//            rgb
//        );
//    }
    
//    // Scale the image
//    {
//        const size_t heightScaled = 216;
//        const size_t widthScaled = (heightScaled*width)/height;
//        Renderer::Txt rgbScaled = renderer.textureCreate(MTLPixelFormatRGBA32Float, widthScaled, heightScaled);
//        renderer.render("CFAViewer::Shader::ImagePipeline::Scale", rgbScaled,
//            // Texture args
//            rgb
//        );
//        rgb = std::move(rgbScaled);
//    }
    
    // Final display render pass
    Renderer::Txt rgba16 = renderer.textureCreate(MTLPixelFormatRGBA16Float,
        [rgb width], [rgb height], MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead);
    
    renderer.render(rgba16,
        renderer.FragmentShader(ImagePipelineShaderNamespace "Base::Display",
            // Texture args
            rgb
        )
    );
    
    renderer.sync(rgba16);
    renderer.commitAndWait();
    
    const fs::path pngPath = fs::path(path).replace_extension(".png");
    std::cout << pngPath << "\n";
    writePNG(renderer, rgba16, pngPath);
}

static bool isCFAFile(const fs::path& path) {
    return fs::is_regular_file(path) && path.extension() == ".cfa";
}

int main(int argc, const char* argv[]) {
    const char* args[] = {"", "/Users/dave/repos/ffcc/data/AR0330-166-384x216"};
    argc = std::size(args);
    argv = args;
    
    const uint32_t Width = 2304;
    const uint32_t Height = 1296;
    
    Renderer renderer;
    {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        assert(dev);
        
        auto metalLibPath = fs::path(argv[0]).replace_filename("default.metallib");
        id<MTLLibrary> lib = [dev newLibraryWithFile:@(metalLibPath.c_str()) error:nil];
        assert(lib);
        id<MTLCommandQueue> commandQueue = [dev newCommandQueue];
        assert(commandQueue);
        
        renderer = Renderer(dev, lib, commandQueue);
    }
    
    for (int i=1; i<argc; i++) {
        const char* pathArg = argv[i];
        
        // Regular file
        if (isCFAFile(pathArg)) {
            createPNGFromCFA(renderer, Width, Height, pathArg);
        
        // Directory
        } else if (fs::is_directory(pathArg)) {
            for (const auto& f : fs::directory_iterator(pathArg)) {
                if (isCFAFile(f)) {
                    createPNGFromCFA(renderer, Width, Height, f);
                }
            }
        }
    }
    
    return 0;
}
