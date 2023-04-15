#pragma once
#include "GPIO.h"

// OutputPriority: allows a single output to be driven with different values (0, 1, or unspecified)
// with varying priorities (0-7), where the specified value of highest priority wins.
//
// OutputPriority is intentionally not templated on a GPIO to save code space.
class OutputPriority {
public:
    using Priority = uint8_t;
    
    template<typename T>
    OutputPriority(const T&) : _write(T::Write) {}
    
    std::optional<bool> get() {
        for (size_t i=0; i<_Width; i++) {
            if (_Get(_en, i)) return _Get(_val, i);
        }
        return std::nullopt;
    }
    
    void set(Priority pri, std::optional<bool> val) {
        _Set(_en, pri, val.has_value());
        _Set(_val, pri, val.value_or(false));
        _update();
    }
    
private:
    using _WriteFn = void(*)(bool);
    using _Bits = uint8_t;
    static constexpr size_t _Width = sizeof(Priority)*8;
    
    static constexpr _Bits _Mask(Priority pri) { return ((_Bits)1) << pri; }
    static constexpr bool _Get(_Bits bits, Priority pri) { return bits & _Mask(pri); }
    static constexpr void _Set(_Bits& bits, Priority pri, bool b) {
        bits &= ~_Mask(pri);
        if (b) bits |= _Mask(pri);
    }
    
    void _update() {
        const std::optional<bool> val = get();
        if (val) _write(*val);
    }
    
    _Bits _en = 0;
    _Bits _val = 0;
    _WriteFn _write = nullptr;
};
