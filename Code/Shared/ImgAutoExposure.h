#pragma once
#include <cstdint>
#include <algorithm>
#include "Img.h"

namespace Img {

class AutoExposure {
public:
    void update(uint32_t highlightCount, uint32_t shadowCount) {
        const int32_t highlights = std::max((int32_t)128, (int32_t)(highlightCount*Img::StatsSubsampleFactor));
        const int32_t shadows = std::max((int32_t)128, (int32_t)(shadowCount*Img::StatsSubsampleFactor));
        
        constexpr int32_t ShadowThreshold       = 2;
        constexpr int32_t HighlightThreshold    = 8;
        constexpr int32_t QuantumDenom          = 16;
        
        if (shadows >= ShadowThreshold*highlights) {
            const int32_t quantum = (Img::CoarseIntTimeMax - _tint) / QuantumDenom;
            const int32_t adj = (_Log2(shadows)-_Log2(highlights))*quantum;
            _tint += adj;
            
            printf("Increase exposure (adj=%jd)\n", (intmax_t)adj);
        
        } else if (highlights >= HighlightThreshold*shadows) {
            const int32_t quantum = (_tint - 0) / QuantumDenom;
            const int32_t adj = (_Log2(highlights)-_Log2(shadows))*quantum;
            _tint -= adj;
            
            printf("Decrease exposure (adj=%jd)\n", (intmax_t)adj);
        }
        
        _tint = std::clamp(_tint, (int32_t)1, (int32_t)Img::CoarseIntTimeMax);
    }
    
    uint16_t integrationTime() const { return _tint; }
    
private:
    
    template <typename I>
    static I _Log2(I x) {
        if (x == 0) return 0;
        return flsll(x)-1;
    }
    
    int32_t _tint = 1024;
};

} // namespace Img
