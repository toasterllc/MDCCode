#pragma once
#include <cstdint>

#if defined(__MSP430__) && !defined(__LARGE_CODE_MODEL__)
    // MSP430, small memory model
    #define _Abort()                                                    \
        do {                                                            \
            asm volatile("mov pc, r12" : : : );     /* r12 = $PC */     \
            asm volatile("jmp Abort" : : : );       /* call Abort() */  \
            __builtin_unreachable();                                    \
        } while (0)

#elif defined(__MSP430__) && defined(__LARGE_CODE_MODEL__)
    // MSP430, large memory model
    #define _Abort()                                                    \
        do {                                                            \
            asm volatile("mov.a pc, r12" : : : );   /* r12 = $PC */     \
            asm volatile("jmp Abort" : : : );       /* call Abort() */  \
            __builtin_unreachable();                                    \
        } while (0)

#elif defined(__arm__)
    // ARM32
    #define _Abort()                                                    \
        do {                                                            \
            asm volatile("mov r0, pc" : : : );  /* r0 = $PC */          \
            asm volatile("jmp Abort" : : : );   /* call Abort() */      \
            __builtin_unreachable();                                    \
        } while (0)

#else
        #error Task: Unsupported architecture
#endif

#define Assert(x)    if (!(x)) _Abort()
#define AssertArg(x) if (!(x)) _Abort()

// Abort(): provided by client to log the abort and trigger crash
extern "C"
[[noreturn, gnu::used]]
void Abort(uintptr_t addr);
