#pragma once
#include <cstdint>

namespace SD {
    // BlockLen: block size of SD card
    static constexpr uint32_t BlockLen = 512;
    
    using Block = uint32_t;
    
    struct [[gnu::packed]] CardId {
        uint8_t manufacturerId          = 0;
        uint16_t oemId                  = 0;
        uint8_t productName[5]          = {};
        uint8_t productRevision         = 0;
        uint32_t productSerialNumber    = 0;
        uint16_t manufactureDate        = 0;
        uint8_t crc                     = 0;
    };
    
    struct [[gnu::packed]] CardData {
        uint8_t data[15]    = {};
        uint8_t crc         = 0;
    };
};
