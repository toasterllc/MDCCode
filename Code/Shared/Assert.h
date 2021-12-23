#pragma once
#include <stdbool.h>
#include <stdlib.h>

inline void Assert(bool x) {
    if (!x) abort();
}

inline void AssertArg(bool x) {
    if (!x) abort();
}
