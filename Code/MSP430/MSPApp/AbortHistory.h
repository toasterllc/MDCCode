#pragma once
#include "RTC.h"

class AbortHistory {
public:
    enum class Domain : uint16_t {
        Invalid     = 0,
        General     = 1,
        Scheduler   = 2,
        ICE         = 3,
        SD          = 4,
        Img         = 5,
    };
    
    void record(RTC::Sec time, Domain domain, uint16_t line) {
        if (_count >= std::size(_items)) return;
        _items[_count].time = time;
        _items[_count].domain = domain;
        _items[_count].line = line;
        _count++;
    }
    
private:
    struct _Item {
        RTC::Sec time = 0;
        Domain domain = Domain::Invalid;
        uint16_t line = 0;
    };
    
    // volatile so that writes aren't optimized away
    volatile _Item _items[3];
    volatile size_t _count = 0;
};
