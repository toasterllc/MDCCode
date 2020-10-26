#pragma once
#include "Abort.h"
#include <stdbool.h>

inline void Assert(bool x) {
    if (!x) Abort();
}

//#define AssertArg(x)
inline void AssertArg(bool x) {
    if (!x) Abort();
}
