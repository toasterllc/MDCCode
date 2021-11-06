#pragma once
#include <cstdint>
#include <algorithm>
#include "Img.h"

namespace Img {

class AutoExposure {
public:
    void update(uint32_t highlightCount, uint32_t shadowCount) {
        constexpr int32_t ShadowThreshold       = 2;
        constexpr int32_t HighlightThreshold    = 8;
        constexpr int32_t QuantumDenom          = 16;
        
        const int32_t highlights = std::max((int32_t)128, (int32_t)(highlightCount*Img::StatsSubsampleFactor));
        const int32_t shadows = std::max((int32_t)128, (int32_t)(shadowCount*Img::StatsSubsampleFactor));
        
        int32_t quantum = 0;
        if (shadows >= ShadowThreshold*highlights) {
            quantum = (Img::CoarseIntTimeMax - _tint) / QuantumDenom;
        
        } else if (highlights >= HighlightThreshold*shadows) {
            quantum = (_tint - 0) / QuantumDenom;
        }
        
        const int32_t adj = ((int32_t)_Log2(shadows)-(int32_t)_Log2(highlights))*quantum;
        if (adj) {
            _tint += adj;
            _tint = std::max((int32_t)1, std::min((int32_t)Img::CoarseIntTimeMax, _tint));
            //printf("Adjust exposure: %jd\n", (intmax_t)adj);
        }
    }
    
    uint16_t integrationTime() const { return _tint; }
    
private:
    static uint32_t _Log2(uint32_t x) {
        uint32_t r = 0;
        while (x >>= 1) r++;
        return r;
    }
    
    int32_t _tint = 1024;
};

} // namespace Img
