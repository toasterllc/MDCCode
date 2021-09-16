#pragma once
#include <stdbool.h>
#include <stdlib.h>

#define MEOWBUFLEN ((176*1024))
#define MEOWSENDLEN (1<<19)-512

inline void Assert(bool x) {
    if (!x) abort();
}

//#define AssertArg(x)
inline void AssertArg(bool x) {
    if (!x) abort();
}
