#pragma once
#include <msp430.h>
#include "Toastbox/IntState.h"
#include "MSP.h"

namespace RTC {

template <uint32_t T_XT1FreqHz>
class Type {
public:
    
    using Sec = MSP::Sec;
    using Time = MSP::Time;
    
    static constexpr Sec InterruptInterval = 2048;
    static constexpr uint32_t Predivider = 1024;
    static constexpr uint32_t FreqHz = T_XT1FreqHz/Predivider;
    static_assert((T_XT1FreqHz % Predivider) == 0); // Confirm that T_XT1FreqHz is evenly divisible by Predivider
    static constexpr uint16_t InterruptCount = (InterruptInterval*FreqHz)-1;
    static_assert(InterruptCount == ((InterruptInterval*FreqHz)-1)); // Confirm that InterruptCount safely fits in 16 bits
    
    bool enabled() const {
        return RTCCTL != 0;
    }
    
    void init(Sec startTime) {
        _start = startTime;
        _delta = 0;
        
        RTCMOD = InterruptCount;
        RTCCTL = RTCSS__XT1CLK | _RTCPSForPredivider<Predivider>() | RTCSR;
        // "TI recommends clearing the RTCIFG bit by reading the RTCIV register
        // before enabling the RTC counter interrupt."
        RTCIV;
        
        // Enable RTC interrupts
        RTCCTL |= RTCIE;
    }
    
    // time(): returns the current time as a (timeStart,timeDelta) tuple
    // Interrupts must be enabled when calling!
    Time time() const {
        return {_start, _deltaRead()};
    }
    
    void isr() {
        // Accessing `RTCIV` automatically clears the highest-priority interrupt
        switch (__even_in_range(RTCIV, RTCIV__RTCIFG)) {
        case RTCIV__RTCIFG:
            // Update our time
            _delta += InterruptInterval;
            break;
        
        default:
            break;
        }
    }
    
private:
    template <class...>
    static constexpr std::false_type _AlwaysFalse = {};
    
    template <uint16_t T_Predivider>
    static constexpr uint16_t _RTCPSForPredivider() {
             if constexpr (T_Predivider == 1)       return RTCPS__1;
        else if constexpr (T_Predivider == 10)      return RTCPS__10;
        else if constexpr (T_Predivider == 100)     return RTCPS__100;
        else if constexpr (T_Predivider == 1000)    return RTCPS__1000;
        else if constexpr (T_Predivider == 16)      return RTCPS__16;
        else if constexpr (T_Predivider == 64)      return RTCPS__64;
        else if constexpr (T_Predivider == 256)     return RTCPS__256;
        else if constexpr (T_Predivider == 1024)    return RTCPS__1024;
        else static_assert(_AlwaysFalse<T_Predivider>);
    }
    
    // _deltaRead(): reads _delta in an safe, overflow-aware manner
    // Interrupts must be enabled when calling!
    Sec _deltaRead() const {
        // This 2x __deltaRead() loop is necessary to handle the race related to RTCCNT overflowing:
        // When we read _delta and RTCCNT, we don't know if _delta has been updated for the most
        // recent overflow of RTCCNT yet. Therefore we compute the time twice, and if t2>=t1,
        // then we got a valid reading. Otherwise, we got an invalid reading and need to try again.
        for (;;) {
            const Sec t1 = __deltaRead();
            const Sec t2 = __deltaRead();
            if (t2 >= t1) return t2;
        }
    }
    
    Sec __deltaRead() const {
        // Disable interrupts so we can read _delta and RTCCNT atomically.
        // This is especially necessary because reading _delta isn't atomic
        // since it's 32 bits.
        Toastbox::IntState ints(false);
        return _delta + (RTCCNT/FreqHz);
    }
    
    // _start: the absolute time that the system started
    Sec _start;
    
    // _delta: the current delta from `_start`. volatile because _delta is
    // updated from the interrupt context
    volatile Sec _delta;
};

} // namespace RTC
