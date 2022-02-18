#pragma once
#import "Tools/Shared/MetalUtil.h"

namespace MDCStudio {

enum class CFAColor : uint8_t {
    Red     = 0,
    Green   = 1,
    Blue    = 2,
};

class CFADesc {
public:
    CFADesc() {}
    CFADesc(CFAColor tl, CFAColor tr, CFAColor bl, CFAColor br) : desc{{tl,tr},{bl,br}} {}
    
    CFAColor desc[2][2] = {};
    
    template <typename T>
    CFAColor color(T x, T y) MetalConst {
        return desc[y&1][x&1];
    }
    
    template <typename T>
    CFAColor color(T pos) MetalConst {
        return color(pos.x, pos.y);
    }
};

} // namespace MDCStudio
