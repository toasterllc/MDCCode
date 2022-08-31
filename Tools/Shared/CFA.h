#pragma once
#import "MetalUtil.h"

namespace MDCTools {

enum class CFAColor : uint8_t {
    Red     = 0,
    Green   = 1,
    Blue    = 2,
};

struct CFADesc {
    CFAColor desc[2][2] = {};
    
    template <typename T>
    CFAColor color(T x, T y) MetalConst { return desc[y&1][x&1]; }
    
    template <typename T>
    CFAColor color(T pos) MetalConst { return color(pos.x, pos.y); }
};

} // namespace MDCTools
