#import "MetalTypes.h"
#import "ImageFilterTypes.h"

namespace CFAViewer {
namespace ImageFilter {
namespace DefringeTypes {

struct Options {
    CFADesc cfaDesc = {CFAColor::Green, CFAColor::Red, CFAColor::Blue, CFAColor::Green};
    uint32_t rounds = 2;
    float αthresh = 2; // Threshold to allow α correction
    float γthresh = .2; // Threshold to allow γ correction
    float γfactor = .5; // Weight to apply to r̄ vs r when doing γ correction
    float δfactor = 10./16; // Weight to apply to center vs adjacent pixels when
                            // computing derivative, when solving for tile shift
};

struct PolyCoeffs {
    float k[16] = {};
};

enum class Dir : uint8_t {
    X = 0,
    Y = 1,
};

template <typename T>
class ColorDir {
public:
    MetalDevice T& operator()(CFAColor color, Dir dir) {
        return _t[((uint8_t)color)>>1][(uint8_t)dir];
    }
    
    MetalConst T& operator()(CFAColor color, Dir dir) MetalConst {
        return _t[((uint8_t)color)>>1][(uint8_t)dir];
    }
private:
    T _t[2][2] = {}; // _t[color][dir]; only red/blue colors allowed
};

} // namespace DefringeType
} // namespace ImageFilter
} // namespace CFAViewer
