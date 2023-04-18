#pragma once
#include "Assert.h"

[[gnu::always_inline]]
static inline void* _AssertAddress() {
    if constexpr (sizeof(void*) == 2) {
        // Small memory model
        asm volatile("mov (sp), r12" : : : );   // r12 = *sp
        asm volatile("ret" : : : );             // return r12
    } else {
        // Large memory model
        asm volatile("mov.a (sp), r12" : : : ); // r12 = *sp
        asm volatile("ret.a" : : : );           // return r12
    }
}

[[noreturn, gnu::noinline]]
void _Abort() {
    Abort(_AssertAddress());
}
