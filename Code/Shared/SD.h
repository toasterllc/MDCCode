#pragma once
#include <cstdint>

namespace SD {
    // BlockLen: block size of SD card
    static constexpr uint32_t BlockLen = 512;
    
    static constexpr uint32_t CeilToBlockLen(uint32_t len) {
        return ((len+BlockLen-1)/BlockLen)*BlockLen;
    }
};
