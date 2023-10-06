#pragma once
#include <cstdint>

#define Assert(x)       if (!(x)) _Abort()
#define AssertArg(x)    if (!(x)) _Abort()

// Abort(): provided by client to log the abort and trigger crash
extern "C"
[[noreturn, gnu::used]]
void Abort(uintptr_t addr);

[[noreturn]]
[[gnu::always_inline]]
inline void _Abort() {
__Abort:
#if defined(__MSP430__) && !defined(__LARGE_CODE_MODEL__)
    // MSP430, small memory model
    asm volatile("mov %0, r12" : : "i" (&&__Abort) : );     /* r12 = $PC */
    asm volatile("jmp Abort" : : : );                       /* call Abort() */
#elif defined(__MSP430__) && defined(__LARGE_CODE_MODEL__)
    // MSP430, large memory model
    asm volatile("mov.a %0, r12" : : "i" (&&__Abort) : );   /* r12 = $PC */
    asm volatile("jmp Abort" : : : );                       /* call Abort() */
#elif defined(__arm__)
    // ARM32
    asm volatile("mov r0, %0" : : "i" (&&__Abort) : );      /* r0 = $PC */
    asm volatile("b Abort" : : : );                         /* call Abort() */
#elif defined(__APPLE__)
    void abort(void);
    abort();
#else
    #error Task: Unsupported architecture
#endif
    __builtin_unreachable();
}
