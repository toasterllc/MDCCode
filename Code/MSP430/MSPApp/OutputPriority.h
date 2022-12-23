#pragma once
#include "GPIO.h"

template <typename T_Pin>
class OutputPriority {
public:
    enum class Priority {
        High,
        Low,
        _Count,
    };
    
    static std::optional<bool> Get() {
        for (const auto& val : _Vals) {
            if (val) return *val;
        }
        return std::nullopt;
    }
    
    static void Set(Priority pri, std::optional<bool> val) {
        _Vals[(size_t)pri] = val;
        _Update();
    }
    
private:
    static void _Update() {
        const std::optional<bool> val = Get();
        if (val) {
            T_Pin::Write(*val);
        }
    }
    
    static inline std::optional<bool> _Vals[(size_t)Priority::_Count] = {};
};
