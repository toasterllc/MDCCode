#pragma once
#include <cstdint>

namespace MDC {

    struct ImgHeader {
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
    
    using Pixel = uint16_t;
    
    constexpr uint32_t ImgHeaderLen     = sizeof(ImgHeader);
    constexpr uint32_t ImgPixelWidth    = 2304;
    constexpr uint32_t ImgPixelHeight   = 1296;
    constexpr uint32_t ImgChecksumLen   = sizeof(uint32_t);
    constexpr uint32_t ImgNoChecksumLen = ImgHeaderLen + ImgPixelWidth*ImgPixelHeight*sizeof(Pixel);
    constexpr uint32_t ImgLen           = ImgHeaderLen + ImgPixelWidth*ImgPixelHeight*sizeof(Pixel) + ImgChecksumLen;

} // namespace ICE40
