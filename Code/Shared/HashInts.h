#pragma once
#include <cstddef>
#include <cstdint>

template <typename... Ts>
size_t HashInts(Ts... ts) {
    // FNV-1 hash
    const uintmax_t v[] = {(uintmax_t)ts...};
    const uint8_t* b = (uint8_t*)&v;
    size_t hash = (size_t)0xcbf29ce484222325;
    for (size_t i=0; i<sizeof(v); i++) {
        hash *= 0x100000001b3;
        hash ^= b[i];
    }
    return hash;
}
