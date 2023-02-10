#pragma once
#include "GPIO.h"
#include <bitset>

template <typename T_Pin>
class OutputPriority {
public:
    using Priority = uint8_t;
    
    static std::optional<bool> Get() {
        for (size_t i=0; i<_Width; i++) {
            if (_En[i]) return _Val[i];
        }
        return std::nullopt;
    }
    
    static void Set(Priority pri, std::optional<bool> val) {
        _En[pri] = val.has_value();
        _Val[pri] = val.value_or(false);
        _Update();
    }
    
private:
    static void _Update() {
        const std::optional<bool> val = Get();
        if (val) {
            T_Pin::Write(*val);
        }
    }
    
    static constexpr size_t _Width = sizeof(Priority)*8;
    static inline std::bitset<_Width> _En;
    static inline std::bitset<_Width> _Val;
};
