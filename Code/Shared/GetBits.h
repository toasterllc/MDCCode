#pragma once
#include <cstdint>

template<uint8_t T_Idx, typename T>
bool GetBit(const T& bytes) {
    static_assert(T_Idx < sizeof(T)*8);
    
    const uint8_t* b = (const uint8_t*)&bytes;
    const uint8_t byteIdx = sizeof(T)-(T_Idx/8)-1;
    const uint8_t bitIdx = T_Idx%8;
    const uint8_t bitMask = 1<<bitIdx;
    return b[byteIdx] & bitMask;
}

template<uint8_t T_Start, uint8_t T_End, typename T>
uint64_t GetBits(const T& bytes) {
    static_assert(T_Start < sizeof(T)*8);
    static_assert(T_Start >= T_End);
    
    const uint8_t* b = (const uint8_t*)&bytes;
    const uint8_t leftByteIdx = sizeof(T)-(T_Start/8)-1;
    const uint8_t leftByteMask = (1<<((T_Start%8)+1))-1;
    const uint8_t rightByteIdx = sizeof(T)-(T_End/8)-1;
    const uint8_t rightByteMask = ~((1<<(T_End%8))-1);
    uint64_t r = 0;
    for (uint8_t i=leftByteIdx; i<=rightByteIdx; i++) {
        uint8_t tmp = b[i];
        // Mask-out bits we don't want
        if (i == leftByteIdx)   tmp &= leftByteMask;
        if (i == rightByteIdx)  tmp &= rightByteMask;
        // Make space for the incoming bits
        if (i == rightByteIdx) {
            tmp >>= T_End%8; // Shift right the number of unused bits
            r <<= 8-(T_End%8); // Shift left the number of used bits
        } else {
            r <<= 8;
        }
        // Or the bits into place
        r |= tmp;
    }
    return r;
}
