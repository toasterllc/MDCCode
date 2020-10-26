#pragma once
#include "Abort.h"

inline void Assert(bool x) {
    if (!x) Abort();
}

inline void AssertArg(bool x) {
    if (!x) Abort();
}
