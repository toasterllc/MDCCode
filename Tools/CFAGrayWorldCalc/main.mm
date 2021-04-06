#import <Foundation/Foundation.h>
#import <filesystem>
#import "Mmap.h"
#import "ImagePipelineTypes.h"
namespace fs = std::filesystem;

class CFAImage {
public:
    using CFAColor = CFAViewer::ImagePipeline::CFAColor;
    using CFADesc = CFAViewer::ImagePipeline::CFADesc;
    using ImagePixel = CFAViewer::MetalUtil::ImagePixel;
    
    static constexpr int Width = 2304;
    static constexpr int Height = 1296;
    
    CFAImage(const fs::path& path) : _cfa(path) {
        assert(_cfa.len() == Width*Height*sizeof(ImagePixel));
    }
    
    double sample(int x, int y) const {
        using namespace CFAViewer::MetalUtil;
        const ImagePixel*const data = (ImagePixel*)_cfa.data();
        x = _SymClamp(Width, x);
        y = _SymClamp(Height, y);
        return (double)data[Width*y+x]/ImagePixelMax;
    }
    
    CFAColor color(int x, int y) const {
        x = _SymClamp(Width, x);
        y = _SymClamp(Height, y);
        return _CFADesc.color(x,y);
    }
    
//    bool isHighlight(int x, int y) const {
//        constexpr double Thresh = .95;
//        return  sample(x-1,y-1)>=Thresh || sample(x+0,y-1)>=Thresh || sample(x+1,y-1)>=Thresh ||
//                sample(x-1,y+0)>=Thresh || sample(x+0,y+0)>=Thresh || sample(x+1,y+0)>=Thresh ||
//                sample(x-1,y+1)>=Thresh || sample(x+0,y+1)>=Thresh || sample(x+1,y+1)>=Thresh ;
//    }
    
    bool isMidtone(int x, int y) const {
//        return true;
        constexpr double ThreshLo = .05;
        constexpr double ThreshHi = .95;
        const double samples[9] = {
            sample(x-1,y-1), sample(x+0,y-1), sample(x+1,y-1),
            sample(x-1,y+0), sample(x+0,y+0), sample(x+1,y+0),
            sample(x-1,y+1), sample(x+0,y+1), sample(x+1,y+1),
        };
        for (const double s : samples) {
            if (s<ThreshLo || s>ThreshHi) return false;
        }
        return true;
    }
    
    static int _SymClamp(int N, int n) {
        if (n < 0)          return -n;
        else if (n >= N)    return 2*(N-1)-n;
        else                return n;
    }
    
    static const inline CFADesc _CFADesc = {CFAColor::Green, CFAColor::Red, CFAColor::Blue, CFAColor::Green};
    const Mmap _cfa;
};

static void grayWorldCalc(const fs::path& path) {
    CFAImage img(path);
    double avgColor[3] = {};
    size_t avgColorCounts[3] = {};
    for (int y=0; y<CFAImage::Height; y++) {
        for (int x=0; x<CFAImage::Width; x++) {
            if (!img.isMidtone(x,y)) continue; // Only consider midtones
            const auto c = img.color(x,y);
            avgColor[(uint8_t)c] += img.sample(x,y);
            avgColorCounts[(uint8_t)c]++;
        }
    }
    avgColor[0] /= avgColorCounts[0];
    avgColor[1] /= avgColorCounts[1];
    avgColor[2] /= avgColorCounts[2];
    
    const fs::path name(path.filename().replace_extension());
    printf("{ \"%s\", { %f, %f, %f } },\n", name.c_str(), avgColor[0], avgColor[1], avgColor[2]);
}

static bool isCFAFile(const fs::path& path) {
    return fs::is_regular_file(path) && path.extension() == ".cfa";
}

int main(int argc, const char* argv[]) {
    argc = 2;
    argv = (const char*[]){"", "/Users/dave/Desktop/Old/2021:4:4/C5TestSets/Outdoor-5pm-ColorChecker"};
    
    for (int i=1; i<argc; i++) {
        const char* pathArg = argv[i];
        
        // Regular file
        if (isCFAFile(pathArg)) {
            grayWorldCalc(pathArg);
        
        // Directory
        } else if (fs::is_directory(pathArg)) {
            for (const auto& f : fs::directory_iterator(pathArg)) {
                if (isCFAFile(f)) {
                    grayWorldCalc(f);
                }
            }
        }
    }
    return 0;
}
