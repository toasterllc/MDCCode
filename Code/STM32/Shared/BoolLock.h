#pragma once
#include <mutex>
#include "Assert.h"

template <
typename T_Scheduler,
bool& T_Lock
>
class BoolLock {
public:
    // Copy: illegal
    BoolLock(const BoolLock& x) = delete;
    BoolLock& operator=(const BoolLock& x) = delete;
    // Move: allowed
    BoolLock(BoolLock&& x) { swap(x); }
    BoolLock& operator=(BoolLock&& x) { swap(x); return *this; }
    
    // Constructor, unlocked
    BoolLock() {}
    
    // Constructor, locked
    struct LockType {}; static constexpr auto Lock = LockType();
    BoolLock(LockType) {}
    
    ~BoolLock() {
        if (_locked) {
            unlock();
        }
    }
    
    void lock() {
        #warning TODO: uncomment after fixing USB comms
//        Assert(!_locked);
        T_Scheduler::Wait([&] { return !T_Lock; });
        T_Lock = true;
        _locked = true;
    }
    
    void unlock() {
        #warning TODO: uncomment after fixing USB comms
//        Assert(_locked);
//        Assert(T_Lock);
        T_Lock = false;
        _locked = false;
    }
    
    void swap(BoolLock& x) {
        std::swap(_locked, x._locked);
    }
    
private:
    bool _locked = false;
};
