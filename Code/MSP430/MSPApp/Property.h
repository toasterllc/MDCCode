#pragma once

template<
typename T,
auto... T_Changed
>
struct T_Property {
    T_Property() = default;
    T_Property(T x) : _x(x) {}
    // Copy: allowed
    T_Property(const T_Property& x) { *this = x._x; }
    T_Property& operator=(const T_Property& x) { *this = x._x; return *this; }
    // Move: allowed
    T_Property(T_Property&& x) { *this = x._x; }
    T_Property& operator=(T_Property&& x) { *this = x._x; return *this; }
    
    // Cast
    operator T() const { return _x; }
    
    // Assignment
    T_Property& operator=(T x) {
        if (x != _x) {
            _x = x;
            ((T_Changed(), ...));
        }
        return *this;
    }
    
    T _x = {};
};
