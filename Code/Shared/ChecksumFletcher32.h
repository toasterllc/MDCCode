#pragma once
#include <cstdint>
#include <cassert>

uint32_t ChecksumFletcher32(const void* data, size_t len) {
    // TODO: optimize so we don't perform a division each iteration
    assert(!(len % sizeof(uint16_t)));
    const uint16_t* words = (const uint16_t*)data;
    const size_t wordCount = len/sizeof(uint16_t);
    uint32_t a = 0;
    uint32_t b = 0;
    for (size_t i=0; i<wordCount; i++) {
        a = (a+words[i]) % UINT16_MAX;
        b = (b+a) % UINT16_MAX;
    }
    return (b<<16) | a;
}
