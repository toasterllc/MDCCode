#pragma once
#include <cstdint>
#include "Util.h"

namespace Img {
    
    using Word  = uint16_t;
    using Pixel = Word;
    
    struct [[gnu::packed]] Header {
        uint16_t version;       // 16'h4242
        uint16_t imageWidth;    // 16'd2304 == 0x0900
        uint16_t imageHeight;   // 16'd1296 == 0x0510
        
        uint16_t coarseIntTime; // 0x1111
        uint16_t analogGain;    // 0x2222
        
        uint32_t count;         // 0xCAFEBABE
        uint32_t timeStart;     // 0xDEADBEEF
        uint32_t timeDelta;     // 0xBEEFCAFE
        
        uint8_t _pad[10];
    };
    static_assert(sizeof(Header) == 32);
    
//    struct Header {
//        // Section idx=0
//        uint16_t version;       // 0x4242
//        uint16_t imageWidth;    // 0x0900
//        uint16_t imageHeight;   // 0x0510
//        uint16_t _pad0;         // 0x0000
//        // Section idx=1
//        uint32_t count;         // 0xCAFEBABE
//        uint32_t _pad1;         // 0x00000000
//        // Section idx=2
//        uint32_t timestamp;     // 0xDEADBEEF
//        uint32_t _pad2;         // 0x00000000
//        // Section idx=3
//        uint16_t coarseIntTime; // 0x1111
//        uint16_t analogGain;    // 0x2222
//        uint32_t _pad3;         // 0x00000000
//    } __attribute__((packed));
    
    constexpr uint16_t HeaderVersion        = 0x4242;
    
    constexpr uint32_t HeaderLen            = sizeof(Header);
    constexpr uint32_t PixelWidth           = 2304;
    constexpr uint32_t PixelHeight          = 1296;
    constexpr uint32_t PixelCount           = PixelWidth*PixelHeight;
    constexpr uint32_t PixelLen             = PixelCount*sizeof(Pixel);
    constexpr uint32_t ChecksumLen          = sizeof(uint32_t);
    constexpr uint32_t Len                  = HeaderLen + PixelLen + ChecksumLen;
    constexpr uint32_t ChecksumOffset       = Len-ChecksumLen;
    
    // StatsSubsampleFactor: We only sample 1/16 of pixels for highlights/shadows
    constexpr uint16_t StatsSubsampleFactor = 16;
    
    constexpr uint16_t CoarseIntTimeMax     = 16383;
    constexpr uint16_t FineIntTimeMax       = 16383;
    constexpr uint16_t AnalogGainMax        = 63;
    
    // PaddedLen: the length of the image padded to a multiple of 512 bytes
    constexpr uint32_t PaddedLen            = Util::Ceil(Len, (uint32_t)512);

} // namespace Img
