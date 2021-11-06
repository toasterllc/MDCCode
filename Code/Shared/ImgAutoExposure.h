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
        
        if ((shadows >= ShadowThreshold*highlights) ||
            (highlights >= HighlightThreshold*shadows)) {
            
            constexpr int32_t QuantumDenom = 2;
            const int32_t quantum = _tint / QuantumDenom;
            const int32_t adjMin = std::min((int32_t)-16, -_tint/2);
            const int32_t adjMax = std::max((int32_t)16, (Img::CoarseIntTimeMax-_tint)/2);
            const int32_t adj = std::clamp((_Log2(shadows)-_Log2(highlights))*quantum, adjMin, adjMax);
            
            _tint += adj;
            printf("Adjust exposure (adj=%jd range=[%jd %jd] %s)\n", (intmax_t)adj, (intmax_t)adjMin, (intmax_t)adjMax, (adj==adjMin || adj==adjMax ? "### MAXXED ###" : ""));
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
