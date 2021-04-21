#pragma once
#ifdef __METAL_VERSION__
#include <metal_stdlib>
#else
#include <cmath>
#endif

// Mod() is a modulo function that matches MATLAB's implementation,
// which ensures that the sign of the result matches the sign of
// the divisor.
template <typename T>
T Mod(T a, T b) {
    if (b == 0) return a; // From definition of MATLAB mod()
#ifdef __METAL_VERSION__
    const T r = metal::fmod(a, b);
#else
    const T r = std::fmod(a, b);
#endif
    if (r == 0) return 0;
    // If the sign of the remainder doesn't match the divisor,
    // add the divisor to make the signs match.
    if ((r > 0) != (b > 0)) return r+b;
    return r;
}
