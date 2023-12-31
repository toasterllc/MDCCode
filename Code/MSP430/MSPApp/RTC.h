#pragma once
#include <msp430.h>
#include <ratio>
#include "Code/Lib/Toastbox/Scheduler.h"
#include "Code/Lib/Toastbox/Util.h"
#include "Code/Shared/MSP.h"
#include "Code/Shared/Assert.h"
#include "Code/Shared/Time.h"

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
alignas(void*)
struct {
    MSP::TimeState state;
    MSP::TimeAdjustment adjustment;
} _RTCState;

template<typename T_Scheduler, uint32_t T_XT1FreqHz>
class T_RTC {
private:
//    // _TicksForTocks(): templated to work with uint16_t (at runtime) and uint32_t (at compile time)
//    template<typename T_Tocks, typename T_Ticks=uint16_t>
//    static constexpr T_Ticks _TicksForTocks(T_Tocks tocks) {
//        if constexpr (std::is_same_v<T_Tocks, uint16_t>) {
//            // uint16_t argument: verify that the max value for the argument can't overflow due to the multiplication
//            static_assert(std::in_range<T_Tocks>(std::numeric_limits<T_Tocks>::max() * TicksPerTock::num));
//            return ((tocks * (T_Tocks)TicksPerTock::num) / (T_Tocks)TicksPerTock::den);
//        
//        } else {
//            // uint32_t argument: the argument value must be known at compile-time, and our calculation
//            // must not overflow T_Ticks.
//            constexpr auto ticks = ((tocks * TicksPerTock::num) / TicksPerTock::den);
//            static_assert(std::in_range<T_Ticks>(ticks));
//            return ticks;
//        }
//    }
    
    // _TicksForTocks(): uint16_t version (runtime)
    static constexpr Time::Ticks16 _TicksForTocks(uint16_t tocks) {
        // uint16_t argument: verify that the max value for the argument can't overflow due to the multiplication
        static_assert(std::in_range<uint16_t>(std::numeric_limits<uint16_t>::max() * TicksPerTock::num));
        return ((tocks * (uint16_t)TicksPerTock::num) / (uint16_t)TicksPerTock::den);
    }
    
    // _TicksForTocks(): uint32_t version (compile-time)
    template<auto T_Tocks>
    static constexpr Time::Ticks16 _TicksForTocks() {
        constexpr auto ticks = ((T_Tocks * TicksPerTock::num) / TicksPerTock::den);
        static_assert(std::in_range<uint16_t>(ticks));
        return ticks;
    }
    
public:
    static constexpr uint32_t InterruptIntervalTocks = 0x10000; // 0xFFFF+1
    static constexpr Time::Ticks16 InterruptIntervalTicks = _TicksForTocks<InterruptIntervalTocks>();
    static_assert(InterruptIntervalTicks == 32768); // Debug
    static constexpr uint16_t TocksMax = InterruptIntervalTocks-1;
    static_assert(TocksMax == 0xFFFF); // Debug
    static constexpr uint16_t Predivider = 1024;
    
    using TocksFreq = std::ratio<T_XT1FreqHz, Predivider>;
    static_assert(TocksFreq::num == 32); // Debug
    static_assert(TocksFreq::den == 1); // Verify TocksFreq is an integer
    using TocksPeriod = std::ratio_divide<std::ratio<1>, TocksFreq>;
    
    using TicksPerTock = std::ratio_divide<TocksPeriod, Time::TicksPeriod>;
    static_assert(TicksPerTock::num == 1); // Debug
    static_assert(TicksPerTock::den == 2); // Debug
    
    using UsPerTock = std::ratio_divide<TocksPeriod, std::micro>;
    static_assert(UsPerTock::num == 31250); // Debug
    static_assert(UsPerTock::den == 1); // Verify UsPerTock is an integer
    
    // Init(): initialize the RTC subsystem
    // Interrupts must be disabled
    static void Init(const MSP::TimeState* state=nullptr) {
        // Start RTC if it's not yet running, or restart it if we were given a new time
        if (!Enabled() || state) {
            _RTCState = {
                .state = (state ? *state : MSP::TimeState{}),
            };
            
            RTCMOD = TocksMax;
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
            T_Scheduler::Delay(_Us<(3*UsPerTock::num)/2>);
        }
    }
    
    // Enabled(): whether RTC was previously configured
    // This state persists across most resets (PUC, POR, software-triggered BORs)
    static bool Enabled() {
        return RTCCTL != 0;
    }
    
    // Tocks(): returns the current tocks offset from _RTCTime, as tracked by the hardware
    // register RTCCNT.
    //
    // Cannot be called from the interrupt context.
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
                T_Scheduler::Delay(_Us<UsPerTock::num>);
                continue;
            }
            return tocks;
        }
    }
    
    // NowBase(): returns the 'base' of the current time, to which Tocks() is added to get the current
    // absolute time. This function allows clients to safely get the current time from the RTC
    // interrupt context, since calling Now() is forbidden in the interrupt context.
    //
    // Note that when called from the RTC ISR, the return value accurately represents the current time
    // because it just overflowed and therefore RTCCNT==0.
    //
    // Can be called from the interrupt context.
    static Time::Instant NowBase() {
        return _RTCState.state.time + _RTCState.adjustment.value;
    }
    
    // Now(): returns the current time
    // Cannot be called from the interrupt context.
    static Time::Instant Now() {
        // Disable interrupts so that reading _RTCTime and adding RTCCNT to it is atomic
        // (with respect to overflow causing _RTCTime to be updated)
        Toastbox::IntState ints(false);
        // Make sure to read Tocks() before _RTCTime, to ensure that _RTCTime reflects the
        // value read by Tocks(), since Tocks() enables interrupts in some cases, allowing
        // _RTCTime to be updated.
        const uint16_t tocks = Tocks();
        return NowBase() + _TicksForTocks(tocks);
    }
    
    // TicksUntilOverflow(): must be called with interrupts disabled to ensure that the overflow
    // interrupt doesn't occur before the caller finishes using the returned value.
    static Time::Ticks16 TicksUntilOverflow() {
        // Note that the below calculation `(TocksMax-Tocks())+1` will never overflow a uint16_t,
        // because Tocks() never returns 0.
        return _TicksForTocks((TocksMax-Tocks())+1);
    }
    
    static void Adjust(const MSP::TimeAdjustment& adjust) {
        // Disable interrupts to prevent ISR() from accessing _RTCState.adjustment while we update it
        Toastbox::IntState ints(false);
        _RTCState.adjustment = adjust;
    }
    
    static MSP::TimeState TimeState() {
        MSP::TimeState x = _RTCState.state;
        x.time = Now();
        return x;
    }
    
    static void ISR(uint16_t iv) {
        switch (iv) {
        case RTCIV_RTCIF: {
            // Update our time
            _RTCState.state.time += InterruptIntervalTicks;
            
            // Correct time based on our calibration
            MSP::TimeAdjustment& adj = _RTCState.adjustment;
            if (adj.delta) {
                adj.counter += InterruptIntervalTicks;
                while (adj.counter >= adj.interval) {
                    adj.counter -= adj.interval;
                    adj.value += adj.delta;
                }
            }
            break;
        }
        
        default:
            Assert(false);
        }
    }
    
private:
    template<auto T>
    static constexpr auto _Us = T_Scheduler::template Us<T>;
    
    template<uint16_t T_Predivider>
    static constexpr uint16_t _RTCPSForPredivider() {
             if constexpr (T_Predivider == 1)       return RTCPS__1;
        else if constexpr (T_Predivider == 10)      return RTCPS__10;
        else if constexpr (T_Predivider == 100)     return RTCPS__100;
        else if constexpr (T_Predivider == 1000)    return RTCPS__1000;
        else if constexpr (T_Predivider == 16)      return RTCPS__16;
        else if constexpr (T_Predivider == 64)      return RTCPS__64;
        else if constexpr (T_Predivider == 256)     return RTCPS__256;
        else if constexpr (T_Predivider == 1024)    return RTCPS__1024;
        else static_assert(Toastbox::AlwaysFalse_v<T_Predivider>);
    }
    
    static bool _OverflowPending() {
        return RTCCTL & RTCIF;
    }
};
