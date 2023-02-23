#pragma once
#include <msp430.h>
#include "Toastbox/Scheduler.h"
#include "MSP.h"

template <uint32_t T_XT1FreqHz, typename T_XOUTPin, typename T_XINPin>
class RTCType {
private:
    template <typename I>
    static constexpr bool _IsPowerOf2(I x) {
        return x && ((x & (x-1)) == 0);
    }
    
public:
    using Time = MSP::Time;
    
    static constexpr uint32_t InterruptIntervalSec = 2048;
    static constexpr uint32_t Predivider = 1024;
    static constexpr uint32_t FreqHz = T_XT1FreqHz/Predivider;
    static_assert((T_XT1FreqHz % Predivider) == 0); // Confirm that T_XT1FreqHz is evenly divisible by Predivider
    static_assert(_IsPowerOf2(FreqHz)); // Confirm that FreqHz is a power of two for cheap division in _TimeRead()
    static constexpr uint16_t InterruptCount = (InterruptIntervalSec*FreqHz)-1;
    static_assert(InterruptCount == ((InterruptIntervalSec*FreqHz)-1)); // Confirm that InterruptCount safely fits in 16 bits
    
    struct Pin {
        using XOUT  = typename T_XOUTPin::template Opts<GPIO::Option::Sel10>;
        using XIN   = typename T_XINPin::template Opts<GPIO::Option::Sel10>;
    };
    
    static bool Enabled() {
        return RTCCTL != 0;
    }
    
    static void Init(Time time=0) {
        // Prevent interrupts from firing while we update our time / reset the RTC
        Toastbox::IntState ints(false);
        
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
        if (!Enabled() || time) {
            _Time = time;
            
            RTCMOD = InterruptCount;
            RTCCTL = RTCSS__XT1CLK | _RTCPSForPredivider<Predivider>() | RTCSR;
            // "TI recommends clearing the RTCIFG bit by reading the RTCIV register
            // before enabling the RTC counter interrupt."
            RTCIV;
            
            // Enable RTC interrupts
            RTCCTL |= RTCIE;
        }
    }
    
    // TimeRead(): returns the current time, which is either absolute (wall time) or
    // relative (to the device start time), depending on the value supplied to Init().
    //
    // TimeRead() reads _Time in an safe, overflow-aware manner.
    //
    // Interrupts must be *enabled* (not disabled!) when calling to properly handle overflow!
    static Time TimeRead() {
        // This 2x _TimeRead() loop is necessary to handle the race related to RTCCNT overflowing:
        // When we read _Time and RTCCNT, we don't know if _Time has been updated for the most
        // recent overflow of RTCCNT yet. Therefore we compute the time twice, and if t2>=t1,
        // then we got a valid reading. Otherwise, we got an invalid reading and need to try again.
        for (;;) {
            const Time t1 = _TimeRead();
            const Time t2 = _TimeRead();
            if (t2 >= t1) return t2;
        }
    }
    
    static void ISR() {
        // Accessing `RTCIV` automatically clears the highest-priority interrupt
        switch (__even_in_range(RTCIV, RTCIV__RTCIFG)) {
        case RTCIV_RTCIF:
            // Update our time
            _Time += InterruptIntervalSec;
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
    
    static Time _TimeRead() {
        // Disable interrupts so we can read _Time and RTCCNT atomically.
        // This is especially necessary because reading _Time isn't atomic
        // since it's 32 bits.
        Toastbox::IntState ints(false);
        return _Time + (RTCCNT/FreqHz);
    }
    
    // _Time: the current time (either absolute or relative, depending on the
    // value supplied to Init()).
    //
    // _Time is volatile because it's updated from the interrupt context.
    //
    // _Time is stored in BAKMEM (RAM that's retained in LPM3.5) so that
    // it's maintained during sleep.
    //
    // _Time needs to live in the _noinit variant of BAKMEM so that RTC
    // memory is never automatically initialized, because we don't want it
    // to be reset when we abort.
    [[gnu::section(".ram_backup_noinit.main")]]
    static inline volatile Time _Time;
};
