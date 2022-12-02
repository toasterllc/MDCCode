#pragma once
#include <msp430.h>
#include "Toastbox/IntState.h"
#include "MSP.h"

namespace RTC {

template <uint32_t T_XT1FreqHz, typename T_XOUTPin, typename T_XINPin>
class Type {
public:
    using Time = MSP::Time;
    
    static constexpr uint32_t InterruptIntervalSec = 2048;
    static constexpr uint32_t Predivider = 1024;
    static constexpr uint32_t FreqHz = T_XT1FreqHz/Predivider;
    static_assert((T_XT1FreqHz % Predivider) == 0); // Confirm that T_XT1FreqHz is evenly divisible by Predivider
    static constexpr uint16_t InterruptCount = (InterruptIntervalSec*FreqHz)-1;
    static_assert(InterruptCount == ((InterruptIntervalSec*FreqHz)-1)); // Confirm that InterruptCount safely fits in 16 bits
    
    struct Pin {
        using XOUT  = typename T_XOUTPin::template Opts<GPIO::Option::Sel10>;
        using XIN   = typename T_XINPin::template Opts<GPIO::Option::Sel10>;
    };
    
    bool enabled() const {
        return RTCCTL != 0;
    }
    
    void init(Time time) {
        // Decrease the XT1 drive strength to save a little current
        // We're not using this for now because supporting it with LPM3.5 is gross.
        // That's because on a cold start, CSCTL6.XT1DRIVE needs to be set after we
        // clear LOCKLPM5 (to reduce the drive strength after XT1 is running),
        // but on a warm start, CSCTL6.XT1DRIVE needs to be set before we clear
        // LOCKLPM5 (to return the register to its previous state before unlocking).
//        CSCTL6 = (CSCTL6 & ~XT1DRIVE) | XT1DRIVE_0;
        
        // Clear XT1 fault flags
        do {
            CSCTL7 &= ~(XT1OFFG | DCOFFG); // Clear XT1 and DCO fault flag
            SFRIFG1 &= ~OFIFG;
        } while (SFRIFG1 & OFIFG); // Test oscillator fault flag
        
        // Start RTC if it's not yet running, or restart it if we were given a new time
        if (!enabled() || time) {
            _time = time;
            
            RTCMOD = InterruptCount;
            RTCCTL = RTCSS__XT1CLK | _RTCPSForPredivider<Predivider>() | RTCSR;
            // "TI recommends clearing the RTCIFG bit by reading the RTCIV register
            // before enabling the RTC counter interrupt."
            RTCIV;
            
            // Enable RTC interrupts
            RTCCTL |= RTCIE;
        }
    }
    
    // time(): returns the current time, which is either absolute or relative (to the
    // device start time), depending on the value supplied to init()
    // Interrupts must be enabled when calling!
    Time time() const {
        return _timeRead();
    }
    
    void isr() {
        // Accessing `RTCIV` automatically clears the highest-priority interrupt
        switch (__even_in_range(RTCIV, RTCIV__RTCIFG)) {
        case RTCIV_RTCIF:
            // Update our time
            _time += InterruptIntervalSec;
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
    
    // _timeRead(): reads _time in an safe, overflow-aware manner
    // Interrupts must be enabled when calling!
    Time _timeRead() const {
        // This 2x __timeRead() loop is necessary to handle the race related to RTCCNT overflowing:
        // When we read _time and RTCCNT, we don't know if _time has been updated for the most
        // recent overflow of RTCCNT yet. Therefore we compute the time twice, and if t2>=t1,
        // then we got a valid reading. Otherwise, we got an invalid reading and need to try again.
        for (;;) {
            const Time t1 = __timeRead();
            const Time t2 = __timeRead();
            if (t2 >= t1) return t2;
        }
    }
    
    Time __timeRead() const {
        // Disable interrupts so we can read _time and RTCCNT atomically.
        // This is especially necessary because reading _time isn't atomic
        // since it's 32 bits.
        Toastbox::IntState ints(false);
        return _time + (RTCCNT/FreqHz);
    }
    
    // _time: the current time (either absolute or relative, depending on the value supplied to init())
    // volatile because _time is updated from the interrupt context
    volatile Time _time;
};

} // namespace RTC
