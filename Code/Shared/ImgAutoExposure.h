#pragma once
#include <cstdint>
#include <algorithm>
#include "Img.h"

namespace Img {

class AutoExposure {
public:
    static const uint8_t ScoreBest = 0xFF;
    
    void update(uint32_t highlightCount, uint32_t shadowCount) {
        const int32_t highlights = std::max((int32_t)1024, (int32_t)(highlightCount*Img::StatsSubsampleFactor));
        const int32_t shadows = std::max((int32_t)1024, (int32_t)(shadowCount*Img::StatsSubsampleFactor));
        const int8_t delta = (_Log2(shadows) - _Log2(highlights));
        _score = ScoreBest-std::abs(delta);
        
        int32_t quantum = 0;
        if (delta > 0) {
            constexpr int32_t QuantumDenom = 32;
            quantum = (Img::CoarseIntTimeMax - _t) / QuantumDenom;
        
        } else if (delta < 0) {
            constexpr int32_t QuantumDenom = 16;
            quantum = (_t - 0) / QuantumDenom;
        
        } else {
            return;
        }
        
        const int32_t adj = delta*quantum;
        if (adj) {
            _t += adj;
            _t = std::max((int32_t)1, std::min((int32_t)Img::CoarseIntTimeMax, _t));
            printf("Adjust exposure adj=%jd (delta=%jd, score=%jd)\n", (intmax_t)adj, (intmax_t)delta, (intmax_t)_score);
        }
    }
    
    uint16_t integrationTime() const { return _t; }
    uint8_t score() const { return _score; }
    
private:
    // _Log2: Signed result for convenience (since the range is [0,31] for uint32_t arguments)
    static int8_t _Log2(uint32_t x) {
        uint8_t r = 0;
        while (x >>= 1) r++;
        return r;
    }
    
    int32_t _t = 1024;
    uint8_t _score = 0;
};

} // namespace Img
