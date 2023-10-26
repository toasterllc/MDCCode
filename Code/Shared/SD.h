#pragma once
#include <cstdint>
#include "Code/Shared/GetBits.h"

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
static_assert(sizeof(CardId) == 16);

struct [[gnu::packed]] CardData {
    uint8_t data[15]    = {};
    uint8_t crc         = 0;
};

inline uint32_t BlockCapacity(const SD::CardData& cardData) {
    return ((uint32_t)GetBits<69,48>(cardData)+1) * (uint32_t)1024;
}

} // namespace SD
