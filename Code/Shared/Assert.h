#pragma once
#include <stdbool.h>

#warning TODO: we need this forward decl because this file gets included from both C and C++,
#warning TODO: and for some reason including stdlib.h doesnt get us abort()
#ifdef __cplusplus
extern "C"
#endif
void abort();

inline void Assert(bool x) {
    if (!x) abort();
}

inline void AssertArg(bool x) {
    if (!x) abort();
}
