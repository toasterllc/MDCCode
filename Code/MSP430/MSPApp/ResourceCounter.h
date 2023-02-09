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
    
    // Constructor, unlocked
    T_ResourceCounter() {}
    
    // Constructor, locked
    struct LockType {}; static constexpr auto Lock = LockType();
    T_ResourceCounter(LockType) {
        lock();
    }
    
    ~T_ResourceCounter() {
        if (_locked) {
            unlock();
        }
    }
    
    static bool Locked() {
        return T_Counter;
    }
    
    bool locked() const {
        return _locked;
    }
    
    void lock() {
        Assert(!_locked);
        T_Counter++;
        _locked = true;
    }
    
    void unlock() {
        Assert(_locked);
        Assert(T_Counter);
        T_Counter--;
        _locked = false;
    }
    
//    void toggle() {
//        if (_asserted) deassert();
//        else           assert();
//    }
    
    void swap(T_ResourceCounter& x) {
        std::swap(_locked, x._locked);
    }
    
private:
    bool _locked = false;
};
