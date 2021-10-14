#pragma once
#include <cstdint>
#include "Util.h"

namespace Img {
    
    using Word  = uint16_t;
    using Pixel = Word;
    
    struct Header {
        // Section idx=0
        uint16_t version        = 0;    // 0x4242
        uint16_t imageWidth     = 0;    // 0x0900
        uint16_t imageHeight    = 0;    // 0x0510
        uint16_t _pad0          = 0;    // 0x0000
        // Section idx=1
        uint32_t counter        = 0;    // 0xCAFEBABE
        uint32_t _pad1          = 0;    // 0x00000000
        // Section idx=2
        uint32_t timestamp      = 0;    // 0xDEADBEEF
        uint32_t _pad2          = 0;    // 0x00000000
        // Section idx=3
        uint16_t exposure       = 0;    // 0x1111
        uint16_t gain           = 0;    // 0x2222
        uint32_t _pad3          = 0;    // 0x00000000
    } __attribute__((packed));
    
    constexpr uint32_t HeaderLen        = sizeof(Header);
    constexpr uint32_t PixelWidth       = 2304;
    constexpr uint32_t PixelHeight      = 1296;
    constexpr uint32_t PixelCount       = PixelWidth*PixelHeight;
    constexpr uint32_t PixelLen         = PixelCount*sizeof(Pixel);
    constexpr uint32_t ChecksumLen      = sizeof(uint32_t);
    constexpr uint32_t Len              = HeaderLen + PixelLen + ChecksumLen;
    constexpr uint32_t ChecksumOffset   = Len-ChecksumLen;
    
    // PaddedLen: the length of the image padded to a multiple of 512 bytes
    constexpr uint32_t PaddedLen        = Util::Ceil(Len, (uint32_t)512);

} // namespace Img
