#pragma once

#define _Stringify(s) #s
#define Stringify(s) _Stringify(s)

namespace Util {

template <typename T>
constexpr T DivCeil(T n, T d) {
    return (n+d-1) / d;
}

template <typename T>
constexpr T Ceil(T n, T mult) {
    return DivCeil(n, mult) * mult;
}

}; // namespace Util
