#pragma once
#include <cstdint>

// We're not using Assert's domain feature, so to avoid having to define AssertDomain
// for every component that wants to call Assert, define it once here.
constexpr uint8_t AssertDomain = 0;
