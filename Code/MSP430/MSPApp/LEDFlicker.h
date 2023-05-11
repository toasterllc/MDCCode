#pragma once
#include <msp430.h>

template<typename T_Pin, uint32_t T_ACLKFreqHz>
class T_LEDFlicker {
public:
    static void Enabled(bool x) {
        Toastbox::IntState ints(false);
        // Short-circuit if our state hasn't changed
        if (x == Enabled()) return;
        
        if (x) {
            // Additional clock divider = /1
            TA1EX0 = TAIDEX_0;
            // Set value to count to
            TA1CCR0 = _CCRForCount<_Count::num>();
            // Start timer
            // Note that this clears TAIFG in case it was set!
            TA1CTL =
                TASSEL__ACLK    |   // clock source = ACLK
                ID__1           |   // clock divider = /1
                MC__UP          |   // mode = up
                TACLR           |   // reset timer state
                TAIE            ;   // enable interrupt
        
        } else {
            // Stop the timer and mask the interrupt
            // Masking the interrupt seems like a better idea than clearing TAIFG, in case
            // there's a race between us clearing TAIFG + stopping the timer, and a
            // an incoming TAIFG=1.
            TA1CTL &= ~(MC1|MC0|TAIE);
        }
    }
    
    static bool Enabled() {
        return TA1CTL & (MC1|MC0);
    }
    
    static bool ISR(uint16_t iv) {
        switch (iv) {
        case TA1IV_TAIFG:
            return T_Scheduler::Tick();
        default:
            Assert(false);
        }
    }
    
private:
    using _Period = typename T_Scheduler::TicksPeriod;
    using _ACLKPeriod = std::ratio<1,T_ACLKFreqHz>;
    using _Count = std::ratio_divide<_Period,_ACLKPeriod>;
    static_assert(_Count::den == 1); // Check that _Count is an integer
    
    template<auto T_Count>
    static constexpr uint16_t _CCRForCount() {
        constexpr auto ccr = T_Count-1;
        static_assert(std::in_range<uint16_t>(ccr));
        return ccr;
    }
};
