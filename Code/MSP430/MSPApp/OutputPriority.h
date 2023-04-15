#pragma once
#include "GPIO.h"
#include <bitset>

class OutputPriority {
public:
    using Priority = uint8_t;
    
    template<typename T>
    OutputPriority(const T&) : _write(T::Write) {}
    
    std::optional<bool> get() {
        for (size_t i=0; i<_Width; i++) {
            if (_en[i]) return _val[i];
        }
        return std::nullopt;
    }
    
    void set(Priority pri, std::optional<bool> val) {
        _en[pri] = val.has_value();
        _val[pri] = val.value_or(false);
        _update();
    }
    
private:
    using _WriteFn = void(*)(bool);
    
    void _update() {
        const std::optional<bool> val = get();
        if (val) _write(*val);
    }
    
    static constexpr size_t _Width = sizeof(Priority)*8;
    
    std::bitset<_Width> _en;
    std::bitset<_Width> _val;
    _WriteFn _write = nullptr;
};
