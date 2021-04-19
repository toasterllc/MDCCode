#import <filesystem>
#import "Mmap.h"
#import "ImagePipelineTypes.h"

class CFAImage {
public:
    using CFAColor = CFAViewer::ImagePipeline::CFAColor;
    using CFADesc = CFAViewer::ImagePipeline::CFADesc;
    using ImagePixel = CFAViewer::MetalUtil::ImagePixel;
    
    static constexpr int Width = 2304;
    static constexpr int Height = 1296;
    
    CFAImage(const std::filesystem::path& path) : _cfa(path) {
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
