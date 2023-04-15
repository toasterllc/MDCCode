#pragma once
#include "AssertionCounter.h"
#include "Assert.h"

// T_SuppressibleAssertion: a AssertionCounter::Assertion that has the additional ability to
// suppress the asserted state.
//
// When supress=false, T_SuppressibleAssertion behaves identically to AssertionCounter::Assertion.
//
// When supress=true, T_SuppressibleAssertion defers acquire()/release() until exiting
// the suppressed state (via suppress(false)).
template<AssertionCounter& T_AssertionCounter>
struct T_SuppressibleAssertion {
    using Assertion = AssertionCounter::Assertion;
    
    void suppress(bool x) {
        // Short-circuit if nothing changed
        if (_suppress == x) return;
        _suppress = x;
        if (_suppress) {
            // Remember if we were asserted for when we unsuppress
            _suppressAsserted = _assertion;
            _assertion = {};
        
        } else {
            if (_suppressAsserted) {
                _assertion = Assertion(T_AssertionCounter);
            }
        }
    }
    
    const Assertion& get() const {
        return _assertion;
    }
    
    void set(Assertion&& x) {
        if (_suppress) {
            _suppressAsserted = x;
        } else {
            _assertion = std::move(x);
        }
    }
    
private:
    using _Assertion = AssertionCounter::Assertion;
    bool _suppress = false;
    bool _suppressAsserted = false;
    AssertionCounter::Assertion _assertion;
};
