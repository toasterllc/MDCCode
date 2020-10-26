#pragma once
#include "abort.h"

inline void assert(bool x) {
    if (!x) abort();
}

inline void AssertParam(bool x) {
    if (!x) abort();
}
