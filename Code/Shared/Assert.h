#pragma once
#include <cstdint>

#define AssertLED(x)        if (!(x)) _AbortLED()
#define AssertNoLED(x)      if (!(x)) _AbortNoLED()

#define AssertArgLED(x)     if (!(x)) _AbortLED()
#define AssertArgNoLED(x)   if (!(x)) _AbortNoLED()

// Abort(): provided by client to log the abort and trigger crash
extern "C"
[[noreturn, gnu::used]]
void AbortLED(uintptr_t addr);

// Abort(): provided by client to log the abort and trigger crash
extern "C"
[[noreturn, gnu::used]]
void AbortNoLED(uintptr_t addr);

[[noreturn]]
[[gnu::always_inline]]
inline void _AbortLED() {
__Abort:
#if defined(__MSP430__) && !defined(__LARGE_CODE_MODEL__)
    // MSP430, small memory model
    asm volatile("mov %0, r12" : : "i" (&&__Abort) : );     /* r12 = $PC */
    asm volatile("jmp Abort" : : : );                       /* call Abort() */
#elif defined(__MSP430__) && defined(__LARGE_CODE_MODEL__)
    // MSP430, large memory model
    asm volatile("mov.a %0, r12" : : "i" (&&__Abort) : );   /* r12 = $PC */
    asm volatile("jmp AbortLED" : : : );                       /* call Abort() */
#elif defined(__arm__)
    // ARM32
    asm volatile("mov r0, %0" : : "i" (&&__Abort) : );      /* r0 = $PC */
    asm volatile("b AbortLED" : : : );                         /* call Abort() */
#elif defined(__APPLE__)
    void abort(void);
    abort();
#else
    #error Task: Unsupported architecture
#endif
    __builtin_unreachable();
}

[[noreturn]]
[[gnu::always_inline]]
inline void _AbortNoLED() {
__Abort:
#if defined(__MSP430__) && !defined(__LARGE_CODE_MODEL__)
    // MSP430, small memory model
    asm volatile("mov %0, r12" : : "i" (&&__Abort) : );     /* r12 = $PC */
    asm volatile("jmp Abort" : : : );                       /* call Abort() */
#elif defined(__MSP430__) && defined(__LARGE_CODE_MODEL__)
    // MSP430, large memory model
    asm volatile("mov.a %0, r12" : : "i" (&&__Abort) : );   /* r12 = $PC */
    asm volatile("jmp AbortNoLED" : : : );                       /* call Abort() */
#elif defined(__arm__)
    // ARM32
    asm volatile("mov r0, %0" : : "i" (&&__Abort) : );      /* r0 = $PC */
    asm volatile("b AbortNoLED" : : : );                         /* call Abort() */
#elif defined(__APPLE__)
    void abort(void);
    abort();
#else
    #error Task: Unsupported architecture
#endif
    __builtin_unreachable();
}
