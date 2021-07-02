#pragma once
#include <stdbool.h>
#include <stdlib.h>

inline void Assert(bool x) {
    if (!x) abort();
}

//#define AssertArg(x)
inline void AssertArg(bool x) {
    if (!x) abort();
}
