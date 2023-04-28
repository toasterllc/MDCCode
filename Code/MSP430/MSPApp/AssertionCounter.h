#pragma once
#include "Assert.h"

template<
auto T_UpdateFn = nullptr
>
class T_AssertionCounter {
public:
    // Copy/move: illegal
    T_AssertionCounter(const T_AssertionCounter& x) = delete;
    T_AssertionCounter& operator=(const T_AssertionCounter& x) = delete;
    T_AssertionCounter(T_AssertionCounter&& x) = delete;
    T_AssertionCounter& operator=(T_AssertionCounter&& x) = delete;
    
    struct Assertion {
        Assertion(bool x=false) : _asserted(x) { if (_asserted) _Assert(); }
        // Copy: illegal
        Assertion(const Assertion& x) = delete;
        Assertion& operator=(const Assertion& x) = delete;
        // Move: allowed
        Assertion(Assertion&& x) { swap(x); }
        Assertion& operator=(Assertion&& x) { swap(x); return *this; }
        ~Assertion() { if (_asserted) _Deassert(); }
        operator bool() const { return _asserted; }
        void swap(Assertion& x) { std::swap(_asserted, x._asserted); }
    private:
        bool _asserted = false;
    };
    
    static bool Asserted() { return _Counter; }
    
private:
    static void _Assert() {
        _Counter++;
        if constexpr (!std::is_null_pointer_v<decltype(T_UpdateFn)>) {
            if (_Counter == 1) {
                T_UpdateFn();
            }
        }
    }
    
    static void _Deassert() {
        Assert(_Counter);
        _Counter--;
        if constexpr (!std::is_null_pointer_v<decltype(T_UpdateFn)>) {
            if (_Counter == 0) {
                T_UpdateFn();
            }
        }
    }
    
    static inline uint8_t _Counter = 0;
};
