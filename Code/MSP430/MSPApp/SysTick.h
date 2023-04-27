#pragma once
#include <msp430.h>

template <uint32_t T_SMCLKFreqHz, uint32_t T_TickPeriodUs>
class T_SysTick {
public:
    // Init(): init WDT timer to act as our SysTick timer
    // Interrupts must be disabled
    static void Init() {
        // Config watchdog timer:
        //   WDTPW:             password
        //   WDTSSEL__SMCLK:    watchdog source = SMCLK
        //   WDTTMSEL:          interval timer mode
        //   WDTCNTCL:          clear counter
        //   WDTIS:             interval
        WDTCTL = WDTPW | WDTHOLD | WDTSSEL__SMCLK | WDTTMSEL | _WDTIS();
        SFRIE1 |= WDTIE; // Enable WDT interrupt
    }
    
    static void Enabled(bool x) {
        Toastbox::IntState ints(false);
        // Short-circuit if our state hasn't changed
        if (x == Enabled()) return;
        
        if (x) {
            WDTCTL |= WDTCNTCL; // Clear count
            SFRIFG1 &= ~WDTIFG; // Clear pending interrupt
            WDTCTL &= ~WDTHOLD; // Enable timer
        
        } else {
            WDTCTL |= WDTHOLD;
        }
    }
    
    static bool Enabled() {
        return !(WDTCTL & WDTHOLD);
    }
    
private:
    template <class...> static constexpr std::false_type _AlwaysFalse = {};
    
    static constexpr uint16_t _WDTIS() {
        constexpr uint64_t K = 1024;
        constexpr uint64_t M = 1024*K;
        constexpr uint64_t G = 1024*M;
        constexpr uint64_t divisor = ((uint64_t)T_TickPeriodUs * (uint64_t)T_SMCLKFreqHz) / UINT64_C(1000000);
        
        if constexpr (divisor == 64) {
            return WDTIS__64;
        } else if constexpr (divisor == 512) {
            return WDTIS__512;
        } else if constexpr (divisor == 8192) {
            return WDTIS__8192;
        } else if constexpr (divisor == 32*K) {
            return WDTIS__32K;
        } else if constexpr (divisor == 512*K) {
            return WDTIS__512K;
        } else if constexpr (divisor == 8192*K) {
            return WDTIS__8192K;
        } else if constexpr (divisor == 128*M) {
            return WDTIS__128M;
        } else if constexpr (divisor == 2*G) {
            return WDTIS__2G;
        } else {
            static_assert(_AlwaysFalse<T_SMCLKFreqHz>);
        }
    }
    
    static inline bool _Enabled = false;
};
