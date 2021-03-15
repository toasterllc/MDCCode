#import "MetalTypes.h"

namespace CFAViewer {
namespace ImageFilter {
namespace DefringeTypes {

struct Options {
    CFADesc cfaDesc = {CFAColor::Green, CFAColor::Red, CFAColor::Blue, CFAColor::Green};
    float αthresh = 2; // Threshold to allow α correction
    float γthresh = .2; // Threshold to allow γ correction
    float γfactor = .5; // Weight to apply to r̄ vs r when doing γ correction
    uint32_t iterations = 2;
};

} // namespace DefringeType
} // namespace ImageFilter
} // namespace CFAViewer
