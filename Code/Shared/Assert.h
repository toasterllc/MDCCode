#pragma once
#include <cstdint>

// Abort(): provided by client to log the abort and trigger crash
[[noreturn]]
void Abort(uintptr_t addr);

#define Assert(x)    if (!(x)) ::_Abort()
#define AssertArg(x) if (!(x)) ::_Abort()

[[gnu::always_inline]]
inline uintptr_t _AssertAddress() {
    if constexpr (sizeof(void*) == 2) {
        // Small memory model
        asm volatile("mov @sp, r12" : : : );    // r12 = *sp
        asm volatile("ret" : : : );             // return r12
    } else {
        // Large memory model
        asm volatile("mov.a @sp, r12" : : : );  // r12 = *sp
        asm volatile("ret.a" : : : );           // return r12
    }
    return 0;
}

[[noreturn, gnu::noinline]]
inline void _Abort() {
    Abort(_AssertAddress());
}
