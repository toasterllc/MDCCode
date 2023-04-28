#pragma once
#include <msp430.h>
#include "Startup.h"
#include "Clock.h"

// T_Watchdog: watchdog timer to reset the device if the watchdog isn't pet periodically.
// The timeout period is defined by T_TimeoutTicks; if the watchdog isn't pet during that
// time, a PUC is triggered, and T_Watchdog then triggers a full BOR upon the next Init().
template<typename T_ACLKFreq, Clock::Ticks T_TimeoutTicks>
class T_Watchdog {
public:
    using ACLKPeriod = std::ratio_divide<std::ratio<1>, T_ACLKFreq>;
    
    static constexpr std::chrono::seconds TimeoutPeriod = std::chrono::duration_cast<std::chrono::seconds>(T_TimeoutTicks);
    static_assert(Clock::Ticks(TimeoutPeriod) == T_TimeoutTicks); // Verify that conversion to seconds is exact
    
    static constexpr std::chrono::seconds ACLKPeriod = 
    
    TimeoutPeriod * ACLKPeriod
    
//    using TimeoutPeriod = std::ratio<T_TimeoutTicks*Time::TicksPeriod::num, Time::TicksPeriod::den>;
//    static_assert(TimeoutPeriod::num == 4096); // Debug
//    static_assert(TimeoutPeriod::den == 1); // Debug
//    using TimeoutFreq = std::ratio_divide<std::ratio<1>, TimeoutPeriod>;
    
    // ACLKPeriodMultiplier = (period want) / (period have)
    using ACLKPeriodMultiplier = std::ratio_divide<TimeoutPeriod, ACLKPeriod>;
    static_assert(ACLKPeriodMultiplier::num == (uint32_t)134217728); // Debug
    static_assert(ACLKPeriodMultiplier::den == 1); // Debug
    
    using ACLKFreqDivider = ACLKPeriodMultiplier;
    
    // Init(): init WDT timer
    // Interrupts must be disabled
    static void Init() {
        // Trigger a full BOR if we were reset due to a WDT timeout (which only triggers a PUC, and we want a full BOR)
        if (Startup::ResetReason() == SYSRSTIV_WDTTO) {
            Assert(false);
        }
        
        // Config watchdog timer
        WDTCTL =
            WDTPW         | // password
            WDTSSEL__ACLK | // source clock = ACLK
            WDTCNTCL      | // clear count
            _WDTIS()      ; // interval
    }
    
//    static void Enabled(bool x) {
//        Toastbox::IntState ints(false);
//        // Short-circuit if our state hasn't changed
//        if (x == Enabled()) return;
//        
//        if (x) {
//            WDTCTL |= WDTCNTCL; // Clear count
//            SFRIFG1 &= ~WDTIFG; // Clear pending interrupt
//            WDTCTL &= ~WDTHOLD; // Enable timer
//        
//        } else {
//            WDTCTL |= WDTHOLD;
//        }
//    }
//    
//    static bool Enabled() {
//        return !(WDTCTL & WDTHOLD);
//    }
    
    static void Pet() {
        WDTCTL |= WDTPW | WDTCNTCL;
    }
    
private:
    template <class...> static constexpr std::false_type _AlwaysFalse = {};
    
    static constexpr uint16_t _WDTIS() {
        constexpr uint32_t K = 1024;
        constexpr uint32_t M = 1024*K;
        constexpr uint32_t G = 1024*M;
        
        // Only integers are allowed for WDTIS and therefore ACLKFreqDivider
        static_assert(ACLKFreqDivider::den == 1);
        constexpr uint32_t divider = ACLKFreqDivider::num;
        
        if constexpr (divider == 64) {
            return WDTIS__64;
        } else if constexpr (divider == 512) {
            return WDTIS__512;
        } else if constexpr (divider == 8192) {
            return WDTIS__8192;
        } else if constexpr (divider == 32*K) {
            return WDTIS__32K;
        } else if constexpr (divider == 512*K) {
            return WDTIS__512K;
        } else if constexpr (divider == 8192*K) {
            return WDTIS__8192K;
        } else if constexpr (divider == 128*M) {
            return WDTIS__128M;
        } else if constexpr (divider == 2*G) {
            return WDTIS__2G;
        } else {
            static_assert(_AlwaysFalse<T_ACLKFreq>);
        }
    }
};
