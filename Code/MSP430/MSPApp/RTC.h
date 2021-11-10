#pragma once
#include <msp430.h>
#include "Toastbox/IRQState.h"

template <uint32_t XT1FreqHz>
class RTCType {
public:
    using Sec = uint32_t;
    
    static constexpr Sec InterruptInterval = 2048;
    static constexpr uint32_t Predivider = 1024;
    static constexpr uint32_t FreqHz = XT1FreqHz/Predivider;
    static_assert((XT1FreqHz % Predivider) == 0); // Confirm that XT1FreqHz is evenly divisible by Predivider
    static constexpr uint16_t InterruptCount = (InterruptInterval*FreqHz)-1;
    static_assert(InterruptCount == ((InterruptInterval*FreqHz)-1)); // Confirm that InterruptCount safely fits in 16 bits
    
    static void Init() {
        RTCMOD = InterruptCount;
        static_assert(Predivider == 1024); // Make sure we're using the right RTCPS flag (RTCPS__1024)
        RTCCTL = RTCSS__XT1CLK | RTCPS__1024 | RTCSR | RTCIE;
    }
    
    static Sec CurrentTime() {
        // This 2x _ReadTime() loop is necessary to handle the race related to RTCCNT overflowing:
        // When we read _Time and RTCCNT, we don't know if _Time has been updated for the most
        // recent overflow of RTCCNT yet. Therefore we compute the time twice, and if t2>=t1,
        // then we got a valid reading. Otherwise, we got an invalid reading and need to try again.
        for (;;) {
            const Sec t1 = _ReadTime();
            const Sec t2 = _ReadTime();
            if (t2 >= t1) return t2;
        }
    }
    
    static void ISR() {
        // Accessing `RTCIV` automatically clears the highest-priority interrupt
        switch (__even_in_range(RTCIV, RTCIV__RTCIFG)) {
        case RTCIV__RTCIFG:
            // Update our time
            _Time += InterruptInterval;
            break;
        
        default:
            break;
        }
    }
    
private:
    
    static Sec _ReadTime() {
        // Disable interrupts so we can read _Time and RTCCNT atomically.
        // This is especially necessary because reading _Time isn't atomic
        // since it's 32 bits.
        Toastbox::IRQState irq = Toastbox::IRQState::Disabled();
        return _Time + (RTCCNT/FreqHz);
    }
    
    static volatile inline Sec _Time = 0; // Marked volatile since it's updated with an interrupt
};
