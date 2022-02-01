#include <cstdint>

static bool GetBit(const uint8_t* bytes, size_t len, uint8_t idx) {
    AssertArg(idx < len*8);
    const uint8_t byteIdx = len-(idx/8)-1;
    const uint8_t bitIdx = idx%8;
    const uint8_t bitMask = 1<<bitIdx;
    return bytes[byteIdx] & bitMask;
}

static uint64_t GetBits(const uint8_t* bytes, size_t len, uint8_t start, uint8_t end) {
    AssertArg(start < len*8);
    AssertArg(start >= end);
    const uint8_t leftByteIdx = len-(start/8)-1;
    const uint8_t leftByteMask = (1<<((start%8)+1))-1;
    const uint8_t rightByteIdx = len-(end/8)-1;
    const uint8_t rightByteMask = ~((1<<(end%8))-1);
    uint64_t r = 0;
    for (uint8_t i=leftByteIdx; i<=rightByteIdx; i++) {
        uint8_t tmp = bytes[i];
        // Mask-out bits we don't want
        if (i == leftByteIdx)   tmp &= leftByteMask;
        if (i == rightByteIdx)  tmp &= rightByteMask;
        // Make space for the incoming bits
        if (i == rightByteIdx) {
            tmp >>= end%8; // Shift right the number of unused bits
            r <<= 8-(end%8); // Shift left the number of used bits
        } else {
            r <<= 8;
        }
        // Or the bits into place
        r |= tmp;
    }
    return r;
}
