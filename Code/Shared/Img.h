#pragma once
#include <cstdint>
#include "Util.h"

namespace Img {
    
    using Word  = uint16_t;
    using Pixel = Word;
    using Id = uint64_t;
    
    struct [[gnu::packed]] Header {
        union [[gnu::packed]] MagicNumber24 {
            uint32_t u24:24;
            uint8_t b3[3] = {};
        };
        static_assert(sizeof(MagicNumber24) == 3);
        
        static constexpr MagicNumber24 MagicNumber  = { 0xC0FFEE };
        static constexpr uint8_t Version            = 0;
        
        MagicNumber24 magic;
        uint8_t version;
        
        uint16_t imageWidth;    // 16'd2304 == 0x0900
        uint16_t imageHeight;   // 16'd1296 == 0x0510
        
        uint16_t coarseIntTime; // 0x1111
        uint16_t analogGain;    // 0x2222
        
        Id id;                  // 0xA7A6A5A4A3A2A1A0
        uint64_t timestamp;     // 0xB7B6B5B4B3B2B1B0
        
        uint8_t _pad[4];
    };
    static_assert(sizeof(Header) == 32);
    
    enum class Size : uint8_t {
        Full,
        Thumb,
    };
    
    constexpr uint32_t ChecksumLen          = sizeof(uint32_t);
    constexpr uint32_t PixelsOffset         = sizeof(Header);
    
    namespace Full {
        constexpr uint32_t PixelWidth           = 2304;
        constexpr uint32_t PixelHeight          = 1296;
        constexpr uint32_t PixelCount           = PixelWidth*PixelHeight;
        constexpr uint32_t PixelLen             = PixelCount*sizeof(Pixel);
        constexpr uint32_t ImageLen             = sizeof(Header) + PixelLen + ChecksumLen;
        constexpr uint32_t ChecksumOffset       = ImageLen-ChecksumLen;
    };
    
    namespace Thumb {
        constexpr uint32_t PixelWidth           = Full::PixelWidth/4;
        constexpr uint32_t PixelHeight          = Full::PixelHeight/4;
        constexpr uint32_t PixelCount           = PixelWidth*PixelHeight;
        constexpr uint32_t PixelLen             = PixelCount*sizeof(Pixel);
        constexpr uint32_t ImageLen             = sizeof(Header) + PixelLen + ChecksumLen;
        constexpr uint32_t ChecksumOffset       = ImageLen-ChecksumLen;
    };
    
    // StatsSubsampleFactor: We only sample 1/16 of pixels for highlights/shadows
    constexpr uint16_t StatsSubsampleFactor = 16;
    
    constexpr uint16_t CoarseIntTimeMax     = 16383;
    constexpr uint16_t FineIntTimeMax       = 16383;
    constexpr uint16_t AnalogGainMax        = 63;

} // namespace Img
