#pragma once
#include "IRQState.h"

class ChannelSelect {
public:
    static void Start() {
        _irqState.disable();
    }
    
    static void End() {
        _irqState.restore();
    }
    
    static void Wait() {
        IRQState::Sleep();
        End();
    }
    
private:
    static inline IRQState _irqState;
};

template <typename T, size_t N>
class Channel {
public:
    class ReadResult {
    public:
        ReadResult() {}
        ReadResult(const T& x) : _x(x), _e(true) {}
        constexpr operator bool() const { return _e; }
        constexpr const T& operator*() const& { return _x; }
    
    private:
        T _x;
        bool _e = false;
    };
    
    T read() {
        for (;;) {
            IRQState irq;
            irq.disable();
            if (_canRead()) return _read();
            IRQState::Sleep();
        }
    }
    
    ReadResult readTry() {
        IRQState irq;
        irq.disable();
        if (_canRead()) return _read();
    }
    
    ReadResult readSelect() {
        if (!_canRead()) return ReadResult();
        auto r = _read();
        ChannelSelect::End();
        return r;
    }
    
    void write(const T& x) {
        for (;;) {
            IRQState irq;
            irq.disable();
            if (_canWrite()) {
                _write(x);
                return;
            }
            IRQState::Sleep();
        }
    }
    
    bool writeTry(const T& x) {
        IRQState irq;
        irq.disable();
        if (!_canWrite()) return false;
        _write(x);
        return true;
    }
    
    bool writeSelect(const T& x) {
        if (!_canWrite()) return false;
        _write(x);
        ChannelSelect::End();
        return true;
    }
    
    void reset() {
        _rptr = 0;
        _wptr = 0;
        _full = 0;
    }
    
private:
    bool _canRead() {
        return (_rptr!=_wptr || _full);
    }
    
    T _read() {
        T r = _buf[_rptr];
        _rptr++;
        // Wrap _rptr to 0
        if (_rptr == N) _rptr = 0;
        _full = false;
        // Memory barrier to ensure previous writes are
        // complete before enabling interrupts
        __DMB();
        return r;
    }
    
    bool _canWrite() {
        return !_full;
    }
    
    void _write(const T& x) {
        _buf[_wptr] = x;
        _wptr++;
        // Wrap _wptr to 0
        if (_wptr == N) _wptr = 0;
        // Update `_full`
        _full = (_rptr == _wptr);
        // Memory barrier to ensure previous writes are
        // complete before enabling interrupts
        __DMB();
    }
    
    T _buf[N];
    size_t _rptr = 0;
    size_t _wptr = 0;
    bool _full = false;
};
