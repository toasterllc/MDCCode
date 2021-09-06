#pragma once
#include <stdbool.h>
#include <stdlib.h>

#define MEOWBUFLEN ((176*1024))

inline void Assert(bool x) {
    if (!x) abort();
}

//#define AssertArg(x)
inline void AssertArg(bool x) {
    if (!x) abort();
}
