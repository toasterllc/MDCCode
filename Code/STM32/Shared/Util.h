#pragma once

template <typename T>
constexpr T DivCeil(T n, T d) {
    return (n+d-1) / d;
}

#define _Stringify(s) #s
#define Stringify(s) _Stringify(s)
