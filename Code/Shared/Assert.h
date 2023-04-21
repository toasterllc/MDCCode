#pragma once
#include <cstdint>

#define Assert(x)    if (!(x)) ::_Abort()
#define AssertArg(x) if (!(x)) ::_Abort()

// Abort(): provided by client to log the abort and trigger crash
extern "C"
[[noreturn, gnu::used]]
void Abort(uintptr_t addr);

[[noreturn]]
[[gnu::always_inline]] // PC read directly from surrounding context
inline void _Abort() {
    if constexpr (sizeof(void*) == 2) {
        // Small memory model
        asm volatile("mov pc, r12" : : : );     // r12 = $PC
        asm volatile("jmp Abort" : : : );       // call Abort()
    } else {
        // Large memory model
        asm volatile("mov.a pc, r12" : : : );   // r12 = $PC
        asm volatile("jmp Abort" : : : );       // call Abort()
    }
    __builtin_unreachable();
}
