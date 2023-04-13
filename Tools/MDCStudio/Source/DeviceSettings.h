#pragma once
#include <vector>
#include <chrono>
#include "date/date.h"
#include "Calendar.h"

namespace MDCStudio {
namespace DeviceSettings {

using Ms = std::chrono::duration<uint32_t, std::milli>;

struct [[gnu::packed]] DayCount {
    uint32_t x;
};

struct [[gnu::packed]] Repeat {
    enum class Type : uint8_t {
        Daily,
        DaysOfWeek,
        DaysOfYear,
        DayInterval,
    };
    
    Type type;
    union {
        Calendar::DaysOfWeek DaysOfWeek;
        Calendar::DaysOfYear DaysOfYear;
        DayCount DayInterval;
    };
};

enum class LEDs : uint8_t {
    None  = 0,
    Green = 1<<0,
    Red   = 1<<1,
};

struct [[gnu::packed]] Duration {
    enum class Unit : uint8_t {
        Seconds,
        Minutes,
        Hours,
        Days,
    };
    
    float value;
    Unit unit;
};

inline Ms MsForDuration(const Duration& x) {
    #warning TODO: how does this handle overflow? how do we want to handle overflow -- throw?
    switch (x.unit) {
    case Duration::Unit::Seconds: return std::chrono::seconds((long)x.value);
    case Duration::Unit::Minutes: return std::chrono::minutes((long)x.value);
    case Duration::Unit::Hours:   return std::chrono::hours((long)x.value);
    case Duration::Unit::Days:    return date::days((long)x.value);
    default:                      abort();
    }
    
//    #warning TODO: how does this handle overflow? do we want to clamp or throw?
//    return std::chrono::seconds((long)_MsForDuration(x));
//    return std::clamp(_MsForDuration(x), 0.f, (float)UINT32_MAX);
}

struct [[gnu::packed]] Capture {
    uint16_t count;
    Duration interval;
    LEDs flashLEDs;
};

struct [[gnu::packed]] CaptureTrigger {
    enum class Type : uint8_t {
        Time,
        Motion,
        Button,
    };
    
    Type type = Type::Time;
    
    union {
        struct [[gnu::packed]] {
            struct [[gnu::packed]] {
                Calendar::TimeOfDay time;
                Repeat repeat;
            } schedule;
            
            Capture capture;
        } time;
        
        struct [[gnu::packed]] {
            struct [[gnu::packed]] {
                struct [[gnu::packed]] {
                    bool enable;
                    Calendar::TimeOfDay start;
                    Calendar::TimeOfDay end;
                } timeRange;
                
                Repeat repeat;
            } schedule;
            
            Capture capture;
            
            struct [[gnu::packed]] {
                struct [[gnu::packed]] {
                    bool enable;
                    Duration duration;
                } suppressDuration;
                
                struct [[gnu::packed]] {
                    bool enable;
                    uint16_t count;
                } maxTriggerCount;
            } constraints;
        } motion;
        
        struct [[gnu::packed]] {
            Capture capture;
        } button;
    };
};

struct [[gnu::packed]] CaptureTriggers {
    CaptureTrigger triggers[32] = {};
    uint8_t count = 0;
};

struct [[gnu::packed]] CaptureTriggersSerialized {
    static constexpr uint16_t Version = 0;
    static constexpr size_t Size = 256;
    union {
        struct [[gnu::packed]] {
            uint16_t version;
            uint8_t payload[Size-2];
        };
        
        uint8_t data[Size] = {};
    };
};
static_assert(sizeof(CaptureTriggersSerialized) == CaptureTriggersSerialized::Size);

template<typename T>
std::vector<uint8_t> _Compress(T begin, T end) {
    std::vector<uint8_t> x;
    for (auto it=begin; it!=end;) {
        if (*it) {
            x.push_back(*it);
            it++;
        } else {
            uint8_t z = 0;
            while (z!=0xff && it!=end && !*it) {
                z++;
                it++;
            }
            x.push_back(0);
            x.push_back(z);
        }
    }
    return x;
}

template<typename T>
std::vector<uint8_t> _Decompress(T begin, T end) {
    std::vector<uint8_t> x;
    for (auto it=begin; it!=end;) {
        if (*it) {
            x.push_back(*it);
            it++;
        } else {
            it++;
            if (it == end) break; // Allow trailing zeroes
            x.insert(x.end(), *it, 0);
            it++;
        }
    }
    return x;
}

template<typename T>
inline void Serialize(T& data, const CaptureTriggers& x) {
    static_assert(sizeof(data) == sizeof(CaptureTriggersSerialized));
    
    CaptureTriggersSerialized s = {
        .version = CaptureTriggersSerialized::Version,
    };
    
    // CaptureTriggers -> CaptureTriggersSerialized
    {
        auto d = _Compress((uint8_t*)&x, (uint8_t*)&x+sizeof(x));
        if (d.size() > sizeof(s.payload)) {
            throw Toastbox::RuntimeError("data doesn't fit in CaptureTriggersSerialized (length: %ju, capacity: %ju)",
                (uintmax_t)d.size(), (uintmax_t)sizeof(s.payload));
        }
        memcpy(s.payload, d.data(), d.size());
    }
    
    // CaptureTriggersSerialized -> data
    {
        memcpy(&data, &s, sizeof(s));
    }
}

template<typename T>
inline void Deserialize(CaptureTriggers& x, const T& data) {
    static_assert(sizeof(data) == sizeof(CaptureTriggersSerialized));
    
    CaptureTriggersSerialized s;
    
    // data -> CaptureTriggersSerialized
    {
        memcpy(&s, &data, sizeof(data));
        
        if (s.version != CaptureTriggersSerialized::Version) {
            throw Toastbox::RuntimeError("CaptureTriggersSerialized version invalid (expected: %ju, got: %ju)",
                (uintmax_t)CaptureTriggersSerialized::Version, (uintmax_t)s.version);
        }
    }
    
    // CaptureTriggersSerialized -> CaptureTriggers
    {
        auto d = _Decompress(s.payload, s.payload+sizeof(s.payload));
        if (d.size() != sizeof(x)) {
            throw Toastbox::RuntimeError("deserialized data length doesn't match sizeof(CaptureTriggers) (expected: %ju, got: %ju)",
                (uintmax_t)sizeof(x), (uintmax_t)d.size());
        }
        memcpy(&x, d.data(), d.size());
        if (x.count > std::size(x.triggers)) {
            throw Toastbox::RuntimeError("invalid deserialized trigger count (got: %ju, max: %ju)",
                (uintmax_t)x.count, (uintmax_t)std::size(x.triggers));
        }
    }
}

} // namespace DeviceSettings
} // namespace MDCStudio
