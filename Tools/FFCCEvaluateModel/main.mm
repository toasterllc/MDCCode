#import <Cocoa/Cocoa.h>
#import <filesystem>
#import <complex>
#import <iostream>
#import <atomic>
#import "Renderer.h"
#import "/Applications/MATLAB_R2021a.app/extern/include/mat.h"
#import "Debug.h"
#import "Mmap.h"
#import "EstimateIlluminantFFCC.h"
using namespace CFAViewer;
using namespace ImagePipeline;
namespace fs = std::filesystem;

MATFile* W_EM = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-EvaluateModel.mat", "r");
MATFile* W_FBVM = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-FitBivariateVonMises.mat", "r");
MATFile* W_FI = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-FeaturizeImage.mat", "r");
MATFile* W_PTD = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-PrecomputeTrainingData.mat", "r");
MATFile* W_CV = matOpen("/Users/dave/repos/MotionDetectorCamera/Tools/FFCCEvaluateModel/Workspace-CrossValidate.mat", "r");

static void processImageFile(Renderer& renderer, const fs::path& path) {
    constexpr size_t W = 2304;
    constexpr size_t H = 1296;
    
    const Mmap cfa(path);
    assert(cfa.len() == W*H*sizeof(MetalUtil::ImagePixel));
    
    // Create a texture from the raw CFA data
    Renderer::Txt raw = renderer.textureCreate(MTLPixelFormatR32Float, W, H);
    renderer.textureWrite(raw, (uint16_t*)cfa.data(), 1, sizeof(uint16_t), MetalUtil::ImagePixelMax);
    
    const CFADesc cfaDesc = {CFAColor::Green, CFAColor::Red, CFAColor::Blue, CFAColor::Green};
    const Color<ColorSpace::Raw> illum = EstimateIlluminantFFCC::Run(renderer, cfaDesc, raw);
    
    printf("{ \"%s\", { %f, %f, %f } },\n",
        path.filename().replace_extension().c_str(),
        illum[0], illum[1], illum[2]
    );
    
//    // Compare illum to MATLAB version
//    {
//        Mat<double,3,1> theirs;
//        load(W_CV, "rgb_est", theirs);
//        assert(rmsdiff(illum, theirs) < 1e-5);
//    }
}

static bool isCFAFile(const fs::path& path) {
    return fs::is_regular_file(path) && path.extension() == ".cfa";
}

int main(int argc, const char* argv[]) {
    // Create renderer
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
    
//    const char* args[] = {"", "/Users/dave/repos/ffcc/data/AR0330/indoor_night2_132.png"};
//    const char* args[] = {"", "/Users/dave/repos/ffcc/data/AR0330"};
    const char* args[] = {"", "/Users/dave/Desktop/Old/2021:4:3/CFAViewerSession-All-FilteredGood"};
    argc = std::size(args);
    argv = args;
    
    for (int i=1; i<argc; i++) {
        const char* pathArg = argv[i];
        
        // Regular file
        if (isCFAFile(pathArg)) {
            processImageFile(renderer, pathArg);
        
        // Directory
        } else if (fs::is_directory(pathArg)) {
            for (const auto& f : fs::directory_iterator(pathArg)) {
                if (isCFAFile(f)) {
                    processImageFile(renderer, f);
                }
            }
        }
    }
    
    return 0;
}
