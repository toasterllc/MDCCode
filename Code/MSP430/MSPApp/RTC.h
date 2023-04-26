#pragma once
#include <msp430.h>
#include <ratio>
#include "Toastbox/Scheduler.h"
#include "MSP.h"
#include "Time.h"
#include "Assert.h"

// _RTCTime: the current time (either absolute or relative, depending on the
// value supplied to Init()).
//
// _RTCTime is volatile because it's updated from the interrupt context.
//
// _RTCTime is stored in BAKMEM (RAM that's retained in LPM3.5) so that
// it's maintained during sleep.
//
// _RTCTime needs to live in the _noinit variant of BAKMEM so that RTC
// memory is never automatically initialized, because we don't want it
// to be reset when we abort.
//
// _RTCTime is declared outside of RTCType because apparently with GCC, the
// gnu::section() attribute doesn't work for static member variables within
// templated classes.

[[gnu::section(".ram_backup_noinit.rtc")]]
static volatile Time::Instant _RTCTime;

template <uint32_t T_XT1FreqHz, typename T_XOUTPin, typename T_XINPin, typename T_Scheduler>
class RTCType {
public:
    static constexpr uint32_t InterruptIntervalSec = 2048;
    static constexpr Time::Ticks InterruptIntervalTicks = InterruptIntervalSec * Time::TicksFreqHz;
    static_assert(InterruptIntervalTicks == 32768); // Debug
    static constexpr uint32_t Predivider = 1024;
    
    using TocksFreqHzRatio = std::ratio<T_XT1FreqHz, Predivider>;
    static_assert(TocksFreqHzRatio::den == 1); // Verify TocksFreqHzRatio division is exact
    static constexpr uint32_t TocksFreqHz = TocksFreqHzRatio::num;
    static_assert(TocksFreqHz == 32); // Debug
    
    using TicksPerTockRatio = std::ratio<Time::TicksFreqHz, TockFreqHz>;
    static_assert(TicksPerTockRatio::num == 1); // Debug
    static_assert(TicksPerTockRatio::den == 2); // Debug
    
    using UsPerTockRatio = std::ratio<1000000, FreqHz>;
    static_assert(UsPerTockRatio::den == 1); // Verify UsPerTockRatio division is exact
    static constexpr uint32_t UsPerTock = UsPerTockRatio::num;
    static_assert(UsPerTock == 31250); // Debug
    
    static constexpr uint16_t TocksMax = 0xFFFF;
    
    static constexpr uint16_t InterruptCount = (InterruptIntervalSec*FreqHz)-1;
    static_assert(InterruptCount == 0xFFFF); // Debug
    
    struct Pin {
        using XOUT  = typename T_XOUTPin::template Opts<GPIO::Option::Sel10>;
        using XIN   = typename T_XINPin::template Opts<GPIO::Option::Sel10>;
    };
    
    static bool Enabled() {
        return RTCCTL != 0;
    }
    
    static void Init(Time::Instant time=0) {
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
            _RTCTime = time;
            
            RTCMOD = InterruptCount;
            RTCCTL = RTCSS__XT1CLK | _RTCPSForPredivider<Predivider>() | RTCSR;
            // "TI recommends clearing the RTCIFG bit by reading the RTCIV register
            // before enabling the RTC counter interrupt."
            RTCIV;
            
            // Enable RTC interrupts
            RTCCTL |= RTCIE;
            
            // Wait until RTC is initialized. This is necessary because before the RTC peripheral is initialized,
            // it's possible to read an old value of RTCCNT, which would temporarily reflect the wrong time.
            // Empirically the RTC peripheral is reset and initialized synchronously from its clock (XT1CLK
            // divided by Predivider), so we wait 1.5 cycles of that clock to ensure RTC is finished resetting.
            T_Scheduler::Delay(T_Scheduler::Us((3*UsPerTock)/2));
        }
    }
    
    // Tocks(): returns the current tocks offset from _RTCTime, as tracked by the hardware
    // register RTCCNT.
    //
    // Guarantee0: Tocks() will never return 0.
    //
    // Guarantee1: if interrupts are disabled before being called, the Tocks() return value
    // can be safely added to _RTCTime to determine the current time.
    // 
    // Guarantee2: if interrupts are disabled before being called, the Tocks() return value
    // can be safely subtracted from TocksMax+1 to determine the number of tocks until the
    // next overflow occurs / ISR() is called.
    //
    // There are 2 special cases that the Tocks() implementation needs handle:
    //
    //   1. RTCCNT=0
    //      If RTCCNT=0, the RTC overflow interrupt has either occurred or hasn't occurred
    //      (empircally [see Tools/MSP430FR2433-RTCTest] it's possible to observe RTCCNT=0
    //      _before_ the RTCIFG interrupt flag is set / before the ISR occurs). So when
    //      RTCCNT=0, we don't know whether ISR() has been called due to the overflow yet,
    //      and therefore we can't provide either Guarantee1 nor Guarantee2. So to handle
    //      this RTCCNT=0 situation we simply wait 1 RTC clock cycle (with interrupts enabled,
    //      which T_Scheduler::Delay() guarantees) to allow RTCCNT to escape 0, therefore
    //      allowing us to provide each Guarantee.
    //
    //   2. RTCIFG=1
    //      It could be the case that RTCIFG=1 upon entry to Tocks() from a previous overflow,
    //      which needs to be explicitly handled to provide Guarantee1 and Guarantee2. We
    //      handle RTCIFG=1 in the same way as the RTCCNT=0: wait 1 RTC clock cycle with
    //      interrupts enabled.
    //
    //      The rationale for why RTCIFG=1 must be explicitly handled to provide the Guarantees
    //      is explained by the following situation: interrupts are disabled, RTCCNT counts
    //      from 0xFFFF -> 0x0 -> 0x1, and then Tocks() is called. In this situation RTCCNT!=0
    //      (because RTCCNT=1) and RTCIFG=1 due to the overflow, and therefore whatever value
    //      RTCCNT contains doesn't reflect the value that should be added to _RTCTime to
    //      get the current time (Guarantee1), because _RTCTime needs to be updated by ISR().
    //      Nor does RTCCNT reflect the number of tocks until the next time ISR() is called
    //      (Guarantee2), because ISR() will be called as soon as interrupts are enabled,
    //      because RTCIFG=1.
    //
    static uint16_t Tocks() {
        for (;;) {
            const uint16_t tocks = RTCCNT;
            if (tocks==0 || _OverflowPending()) {
                T_Scheduler::Delay(T_Scheduler::Us(UsPerTock));
                continue;
            }
            return tocks;
        }
    }
    
    static constexpr Time::Ticks _TicksForTocks(uint16_t tocks) {
        // We don't cast `tocks` to a wider type because currently the ticks/tock ratio is <= 1,
        // so the result will always be smaller. Check that assumption:
        static_assert(TicksPerTockRatio::num <= TicksPerTockRatio::den);
        return ((tocks*TicksPerTockRatio::num)/TicksPerTockRatio::den);
    }
    
    static Time::Instant Now() {
        // Disable interrupts so that reading _RTCTime and adding RTCCNT to it is atomic
        // (with respect to overflow causing _RTCTime to be updated)
        Toastbox::IntState ints(false);
        // Make sure to read tocks before _RTCTime, to ensure that _RTCTime reflects the
        // value read by Tocks(), since Tocks() enables interrupts in some cases,
        // allowing _RTCTime to be updated.
        const uint16_t tocks = Tocks();
        return _RTCTime + _TicksForTocks(tocks);
    }
    
    // TimeUntilOverflow(): must be called with interrupts disabled to ensure that the overflow
    // interrupt doesn't occur before the caller finishes using the returned value.
    static Time::Ticks TimeUntilOverflow() {
        // Note that the below calculation `(TocksMax-Tocks())+1` will never overflow a uint16_t,
        // because Tocks() never returns 0.
        return _TicksForTocks((TocksMax-Tocks())+1);
    }
    
    static void ISR(uint16_t iv) {
        switch (__even_in_range(iv, RTCIV_RTCIF)) {
        case RTCIV_RTCIF:
            // Update our time
            _RTCTime += InterruptIntervalTicks;
            return;
        default:
            Assert(false);
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
    
    static bool _OverflowPending() {
        return RTCCTL & RTCIF;
    }
};
