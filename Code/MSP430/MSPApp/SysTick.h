#pragma once
#include <msp430.h>
#include <ratio>

template<typename T_Scheduler, uint32_t T_ACLKFreqHz>
class T_SysTick {
public:
    static void Init() {
    }
    
    static void Enabled(bool x) {
        Toastbox::IntState ints(false);
        // Short-circuit if our state hasn't changed
        if (x == Enabled()) return;
        
        if (x) {
            // Additional clock divider = /1
            TA0EX0 = TAIDEX_0;
//            // Reset TA0CCTL0
//            TA0CCTL0 = 0;
            // Set value to count to
            TA0CCR0 = _CCRForCount<_Count::num>();
            // Start timer
            // Note that this clears TAIFG in case it was set!
            TA0CTL =
                TASSEL__ACLK    |   // clock source = ACLK
                ID__1           |   // clock divider
                MC__UP          |   // mode = up
                TACLR           |   // reset timer state
                TAIE            ;   // enable interrupt
        
        } else {
            // Stop the timer and mask the interrupt
            // Masking the interrupt seems like a better idea than clearing TAIFG, in case
            // there's a race between us clearing TAIFG + stopping the timer, and a
            // an incoming TAIFG=1.
            TA0CTL &= ~(MC1|MC0|TAIE);
            
            std::ratio<16000000>
            
            __delay_cycles();
            // "A delay of at least 1.5 timer clocks is required to resynchronize before
            // restarting the timer"
            #warning TODO: how should we handle the above comment? it'd be nice if we didn't have to burn 1.5 cycles at 32kHz, which is ~700 MCLK cycles
        }
    }
    
    static bool Enabled() {
        return TA0CTL & 
    }
    
    static bool ISR(uint16_t iv) {
        #warning TODO: check iv
        return T_Scheduler::Tick();
    }
    
    static void _TimerStop() {
        // Stop the timer and mask the interrupt
        // Masking the interrupt seems like a better idea than clearing TAIFG, in case
        // there's a race between us clearing TAIFG + stopping the timer, and a
        // an incoming TAIFG=1.
        TA0CTL &= ~(MC1|MC0|TAIE);
        
        // "A delay of at least 1.5 timer clocks is required to resynchronize before
        // restarting the timer"
        #warning TODO: 
    }
    
    // _Reset(): resets the timer and our state (_ISRState)
    // Interrupts must be disabled
    static void _Reset() {
        _ISRState = {};
        _TimerStop();
    }
    
private:
    using _Period = T_Scheduler::TicksPeriod;
    using _ACLKPeriod = std::ratio<1,T_ACLKFreqHz>;
    using _Count = std::ratio_divide<_Period,_ACLKPeriod>;
    static_assert(_Freq::den == 1); // Check that _Count is an integer
    
    template<auto T_Count>
    static constexpr uint16_t _CCRForCount() {
        constexpr auto ccr = T_Count-1;
        static_assert(std::in_range<uint16_t>(ccr));
        return ccr;
    }
};
