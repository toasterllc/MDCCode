#pragma once
#include "Assert.h"

template <
auto& T_Counter
>
class T_ResourceCounter {
public:
    // Copy: illegal
    T_ResourceCounter(const T_ResourceCounter& x) = delete;
    T_ResourceCounter& operator=(const T_ResourceCounter& x) = delete;
    // Move: allowed
    T_ResourceCounter(T_ResourceCounter&& x) { swap(x); }
    T_ResourceCounter& operator=(T_ResourceCounter&& x) { swap(x); return *this; }
    
    // Constructor, released
    T_ResourceCounter() {}
    
    // Constructor, acquireed
    struct AcquireType {}; static constexpr auto Acquire = AcquireType();
    T_ResourceCounter(AcquireType) {
        acquire();
    }
    
    ~T_ResourceCounter() {
        if (_acquired) {
            release();
        }
    }
    
    static bool Acquired() {
        return T_Counter;
    }
    
    bool acquired() const {
        return _acquired;
    }
    
    void acquire() {
        Assert(!_acquired);
        T_Counter++;
        _acquired = true;
    }
    
    void release() {
        Assert(_acquired);
        Assert(T_Counter);
        T_Counter--;
        _acquired = false;
    }
    
    void swap(T_ResourceCounter& x) {
        std::swap(_acquired, x._acquired);
    }
    
private:
    bool _acquired = false;
};
