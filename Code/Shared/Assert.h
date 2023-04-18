#pragma once
#include <cstdint>

// Abort(): provided by client to log the abort and trigger crash
[[noreturn]]
void Abort(const void* addr);

// _Abort(): internal function that calls client-provided Abort()
// Marked gnu::noinline to ensure caller makes a real function call which makes its
// return address available, so that the assertion location can be determined.
// Shouldn't be marked `noreturn` so that calls aren't reduced to a branch.
[[noreturn, gnu::noinline]]
void _Abort();

#define Assert(x)    if (!(x)) ::_Abort()
#define AssertArg(x) if (!(x)) ::_Abort()
