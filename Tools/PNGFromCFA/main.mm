#import <Cocoa/Cocoa.h>
#import <sys/stat.h>
#import <vector>
#import <string>
#import <filesystem>
#import <iostream>
#import "Mmap.h"
#import "Renderer.h"
#import "ImagePipelineTypes.h"
using namespace CFAViewer;
namespace fs = std::filesystem;

static CGColorSpaceRef SRGBColorSpace() {
    static CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    return cs;
}

static void writePNG(id<MTLTexture> txt, const fs::path& path) {
    const size_t ComponentsPerPixel = 4; // RGBA
    const size_t BytesPerComponent = 2; // 16-bit floats
    const size_t w = [txt width];
    const size_t h = [txt height];
    const size_t bytesPerRow = ComponentsPerPixel*BytesPerComponent*w;
    const uint32_t opts = kCGImageAlphaNoneSkipLast|kCGBitmapFloatComponents|kCGBitmapByteOrder16Little;
    id ctx = CFBridgingRelease(CGBitmapContextCreate(nullptr, w, h, BytesPerComponent*8, bytesPerRow,
        SRGBColorSpace(), opts));
    
    if (!ctx) throw std::runtime_error("CGBitmapContextCreate returned nil");
    
    uint8_t* data = (uint8_t*)CGBitmapContextGetData((CGContextRef)ctx);
    [txt getBytes:data bytesPerRow:bytesPerRow fromRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0];
    
    id img = CFBridgingRelease(CGBitmapContextCreateImage((CGContextRef)ctx));
    if (!img) throw std::runtime_error("CGBitmapContextCreateImage returned nil");
    
    id imgDest = CFBridgingRelease(CGImageDestinationCreateWithURL(
        (CFURLRef)[NSURL fileURLWithPath:@(path.c_str())], kUTTypePNG, 1, nullptr));
    if (!imgDest) throw std::runtime_error("CGImageDestinationCreateWithURL returned nil");
    CGImageDestinationAddImage((CGImageDestinationRef)imgDest, (CGImageRef)img, nullptr);
    CGImageDestinationFinalize((CGImageDestinationRef)imgDest);
}

static void createPNGFromCFA(Renderer& renderer, uint32_t width, uint32_t height, const fs::path& path) {
    using namespace ImagePipeline;
    const CFADesc cfaDesc = {CFAColor::Green, CFAColor::Red, CFAColor::Blue, CFAColor::Green};
    
    const size_t len = sizeof(uint16_t)*width*height;
    const Mmap imgMmap(path.c_str());
    
    // Verify that the file size is what we expect, given the image width/height
    if (imgMmap.len() != len) throw std::runtime_error("invalid length");
    
    // Create a Metal buffer, and copy the image contents into it
    Renderer::Buf imgBuf = renderer.createBuffer(len);
    memcpy([imgBuf contents], imgMmap.data(), len);
    
    Renderer::Txt raw = renderer.createTexture(MTLPixelFormatR32Float, width, height);
    
    // Load `raw`
    renderer.render("CFAViewer::Shader::ImagePipeline::LoadRaw", raw,
        // Buffer args
        cfaDesc,
        width,
        height,
        imgBuf
        // Texture args
    );
    
    Renderer::Txt rgb = renderer.createTexture(MTLPixelFormatRGBA32Float, width, height);
    
    // De-bayer
    renderer.render("CFAViewer::Shader::DebayerBilinear::Debayer", rgb,
        // Buffer args
        cfaDesc,
        // Texture args
        raw
    );
    
    // Final display render pass
    Renderer::Txt rgba16 = renderer.createTexture(MTLPixelFormatRGBA16Float,
        width, height, MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead);
    renderer.render("CFAViewer::Shader::ImagePipeline::Display", rgba16,
        // Texture args
        rgb
    );
    
    renderer.sync(rgba16);
    renderer.commitAndWait();
    
    fs::path pngPath = path;
    pngPath.replace_extension(".png");
    std::cout << pngPath << "\n";
    writePNG(rgba16, pngPath);
}

static bool isCFAFile(const fs::path& path) {
    return fs::is_regular_file(path) && path.extension() == ".cfa";
}

int main(int argc, const char* argv[]) {
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
