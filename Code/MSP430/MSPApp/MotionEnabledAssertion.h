#pragma once
#include "ResourceCounter.h"
#include "Assert.h"

// T_MotionEnabledAssertion: a T_ResourceCounter that has the additional ability to
// suppress the acquired state.
//
// When supress=false, T_MotionEnabledAssertion behaves identically to T_ResourceCounter.
//
// When supress=true, T_MotionEnabledAssertion defers acquire()/release() until exiting
// the suppressed state (via suppress(false)).
template<auto& T_Counter, auto T_AcquireFn, auto T_ReleaseFn>
struct T_MotionEnabledAssertion : T_ResourceCounter<T_Counter, T_AcquireFn, T_ReleaseFn> {
    void suppress(bool x) {
        // Short-circuit if nothing changed
        if (_suppress == x) return;
        _suppress = x;
        if (_suppress) {
            _suppressAcquired = _Super::acquired();
            if (_suppressAcquired) {
                _Super::release();
            }
        
        } else {
            if (_suppressAcquired) {
                _Super::acquire();
            }
        }
    }
    
    void acquire() {
        if (_suppress) {
            Assert(!_suppressAcquired);
            _suppressAcquired = true;
        } else {
            _Super::acquire();
        }
    }
    
    void release() {
        if (_suppress) {
            Assert(_suppressAcquired);
            _suppressAcquired = false;
        } else {
            _Super::release();
        }
    }
    
private:
    using _Super = T_ResourceCounter<T_Counter, T_AcquireFn, T_ReleaseFn>;
    bool _suppress = false;
    bool _suppressAcquired = false;
};
