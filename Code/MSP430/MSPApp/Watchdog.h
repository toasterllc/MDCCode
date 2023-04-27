#pragma once
#include <msp430.h>
#include "Startup.h"

// T_Watchdog: watchdog timer to reset the device if it the watchdog isn't pet periodically.
// The watchdog period is defined by 2 * T_RTC::InterruptIntervalTicks; if the watchdog
// isn't pet during that time, a PUC is triggered, and T_Watchdog then triggers a full BOR
// upon the next Init().
template<typename T_RTC, typename T_ACLKPeriod>
class T_Watchdog {
public:
    static constexpr Time::Ticks TimeoutTicks = T_RTC::InterruptIntervalTicks*2;
    using TimeoutPeriod = std::ratio<TimeoutTicks*Time::TicksPeriod::num, Time::TicksPeriod::den>;
    static_assert(TimeoutPeriod::num == 4096); // Debug
    static_assert(TimeoutPeriod::den == 1); // Debug
    
    // ACLKDivider = (period want) / (period have)
    using ACLKDivider = std::ratio_divide<TimeoutPeriod, T_ACLKPeriod>;
    static_assert(ACLKDivider::num == (uint32_t)134217728); // Debug
    static_assert(ACLKDivider::den == 1); // Debug
    
    // Init(): init WDT timer
    // Interrupts must be disabled
    static void Init() {
        // Trigger a full BOR if we were reset due to a WDT timeout (which only triggers a PUC, and we want a BOR)
        if (Startup::SYSRSTIV() == SYSRSTIV_WDTTO) {
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
        
        // Only integers are allowed for WDTIS and therefore ACLKDivider
        static_assert(ACLKDivider::den == 1);
        constexpr uint32_t divider = ACLKDivider::num;
        
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
            static_assert(_AlwaysFalse<T_ACLKFreqHz>);
        }
    }
};
