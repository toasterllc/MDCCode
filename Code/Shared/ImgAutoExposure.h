#pragma once
#include <cstdint>
#include <algorithm>
#include "Img.h"

namespace Img {

class AutoExposure {
public:
    static constexpr uint8_t ScoreBest = 0xFF;
    
    uint8_t update(uint32_t highlightCount, uint32_t shadowCount) {
        constexpr int8_t AdjustThreshold = 4;
        const int32_t highlights = std::max((int32_t)1024, (int32_t)(highlightCount*Img::StatsSubsampleFactor));
        const int32_t shadows = std::max((int32_t)1024, (int32_t)(shadowCount*Img::StatsSubsampleFactor));
        const int8_t delta = _Log2(shadows)-_Log2(highlights);
        const uint16_t tprev = _t;
        
//        printf("\n\nDELTA: %d\n", delta);
        
        uint32_t t = _t; // u32 to prevent overflow in our math below
        if (delta > AdjustThreshold) {
            t *= delta;
            t /= AdjustThreshold;
            
//            t *= 3;
//            t /= 2;
            
//            t <<= 1;

        } else if (delta < -AdjustThreshold) {
            t *= AdjustThreshold;
            t /= -delta;
            
//            t *= 2;
//            t /= 3;
            
//            t >>= 1;
        }
        
        _t = std::clamp(t, (uint32_t)1, (uint32_t)Img::CoarseIntTimeMax);
//        printf("_t %d -> %d\n", tprev, _t);
        
//        int32_t quantum = 0;
//        if (delta > AdjustThreshold) {
//            constexpr int32_t QuantumDenom = 16;
//            quantum = ((int32_t)Img::CoarseIntTimeMax - (int32_t)_t) / QuantumDenom;
//        
//        } else if (delta < -AdjustThreshold) {
//            constexpr int32_t QuantumDenom = 16;
//            quantum = ((int32_t)_t - 0) / QuantumDenom;
//        }
//        
//        if (quantum) {
//            const int32_t adj = delta*quantum;
//            _t = std::max((int32_t)1, std::min((int32_t)Img::CoarseIntTimeMax, (int32_t)_t + adj));
////             printf("Adjust exposure adj=%jd (delta=%jd)\n", (intmax_t)adj, (intmax_t)delta);
//        }
        
        _changed = (_t != tprev);
        
        const uint8_t score = ScoreBest-std::abs(delta);
        return score;
    }
    
    uint16_t integrationTime() const { return _t; }
    bool changed() const { return _changed; }
    
private:
    // _Log2: Signed result for convenience (since the range is [0,31] for uint32_t arguments)
    static int8_t _Log2(uint32_t x) {
        uint8_t r = 0;
        while (x >>= 1) r++;
        return r;
    }
    
    uint16_t _t = 1024;
    bool _changed = false;
};

} // namespace Img
