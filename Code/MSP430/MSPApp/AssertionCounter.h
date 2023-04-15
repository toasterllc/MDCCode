#pragma once
#include "Assert.h"

class AssertionCounter {
public:
    using Fn = void(*)();
    
    // Constructor
    AssertionCounter() {}
    AssertionCounter(Fn acquire, Fn release) : _acquire(acquire), _release(release) {}
    
    // Copy/move: illegal
    AssertionCounter(const AssertionCounter& x) = delete;
    AssertionCounter& operator=(const AssertionCounter& x) = delete;
    AssertionCounter(AssertionCounter&& x) = delete;
    AssertionCounter& operator=(AssertionCounter&& x) = delete;
    
    struct Assertion {
        Assertion() {}
        Assertion(AssertionCounter& counter) : _counter(&counter) { _counter->_assert(); }
        // Copy: illegal
        Assertion(const Assertion& x) = delete;
        Assertion& operator=(const Assertion& x) = delete;
        // Move: allowed
        Assertion(Assertion&& x) { swap(x); }
        Assertion& operator=(Assertion&& x) { swap(x); return *this; }
        ~Assertion() { if (_counter) _counter->_deassert(); }
        operator bool() const { return _counter; }
        void swap(Assertion& x) { std::swap(_counter, x._counter); }
    private:
        AssertionCounter* _counter = nullptr;
    };
    
    operator bool() const { return _counter; }
    
private:
    void _assert() {
        _counter++;
        if (_acquire) {
            if (_counter == 1) {
                _acquire();
            }
        }
    }
    
    void _deassert() {
        Assert(_counter);
        _counter--;
        if (_release) {
            if (_counter == 0) {
                _release();
            }
        }
    }
    
    Fn _acquire = nullptr;
    Fn _release = nullptr;
    uint8_t _counter = 0;
};
