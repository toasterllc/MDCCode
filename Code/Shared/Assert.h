#pragma once

// Abort(): provided by client
extern "C"
[[noreturn]]
void Abort(uint8_t domain, uint16_t line);

#define Assert(x)    if (!(x)) Abort(AbortDomain, __LINE__)
#define AssertArg(x) if (!(x)) Abort(AbortDomain, __LINE__)
