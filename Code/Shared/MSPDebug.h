#pragma once

namespace MSP::Debug {

struct [[gnu::packed]] LogPacket {
    enum class Type : uint16_t {
        Chars = 0,
        Dec16 = 0x8000, // High bit must be used to disambiguate against ASCII characters
        Dec32,
        Dec64,
        Hex16,
        Hex32,
        Hex64,
    };
    
    union [[gnu::packed]] {
        Type type;
        uint8_t u8[2];
        uint16_t u16 = 0;
    };
};

} // namespace MSP
