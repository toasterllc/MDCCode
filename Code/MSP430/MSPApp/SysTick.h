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
            // Stop timer
            _TimerStop();
            // Additional clock divider = /8
            TA0EX0 = TAIDEX_7;
    //        // Reset TA0CCTL0
    //        TA0CCTL0 = 0;
            // Set value to count to
            TA0CCR0 = ccr;
            // Start timer
            TA0CTL =
                TASSEL__ACLK    |   // clock source = ACLK
                ID__8           |   // clock divider = /8
                MC__UP          |   // mode = up
                TACLR           |   // reset timer state
                TAIE            ;   // enable interrupt
        
        } else {
            
        }
    }
    
    static bool Enabled() {
        
    }
    
    static bool ISR(uint16_t iv) {
        #warning TODO: check iv
        return T_Scheduler::Tick();
    }
    
    
    
    
    
    
    static void _TimerStop() {
        TA0CTL &= ~(MC1|MC0|TAIE);
    }
    
    static void _TimerSet(uint16_t ccr) {
        // Stop timer
        _TimerStop();
        // Additional clock divider = /8
        TA0EX0 = _ID().second;
//        // Reset TA0CCTL0
//        TA0CCTL0 = 0;
        // Set value to count to
        TA0CCR0 = _CCRForCount<_Count::num>();
        // Start timer
        TA0CTL =
            TASSEL__ACLK    |   // clock source = ACLK
            _ID().first     |   // clock divider
            MC__UP          |   // mode = up
            TACLR           |   // reset timer state
            TAIE            ;   // enable interrupt
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
    
    using _Freq = std::ratio_divide<std::ratio<1>, T_Scheduler::TicksPeriod>;
    static_assert(_Freq::den == 1); // Check that our frequency is an integer
    
    // _FreqDivider = (freq have) / (freq want), therefore (freq want) = (freq have) / _FreqDivider
    using _FreqDivider = std::ratio_divide<std::ratio<T_ACLKFreqHz>, _Freq>;
    static_assert(_FreqDivider::den == 1); // Check that our frequency divider is an integer
    
    static constexpr std::pair<uint16_t,uint16_t> _ID() {
             if constexpr (_FreqDivider::num == 1)  return std::make_pair(ID__1, TAIDEX_0);
        else if constexpr (_FreqDivider::num == 2)  return std::make_pair(ID__1, TAIDEX_1);
        else if constexpr (_FreqDivider::num == 3)  return std::make_pair(ID__1, TAIDEX_2);
        else if constexpr (_FreqDivider::num == 4)  return std::make_pair(ID__1, TAIDEX_3);
        else if constexpr (_FreqDivider::num == 5)  return std::make_pair(ID__1, TAIDEX_4);
        else if constexpr (_FreqDivider::num == 6)  return std::make_pair(ID__1, TAIDEX_5);
        else if constexpr (_FreqDivider::num == 7)  return std::make_pair(ID__1, TAIDEX_6);
        else if constexpr (_FreqDivider::num == 8)  return std::make_pair(ID__1, TAIDEX_7);
        
        else if constexpr (_FreqDivider::num == 10) return std::make_pair(ID__2, TAIDEX_4);
        else if constexpr (_FreqDivider::num == 12) return std::make_pair(ID__2, TAIDEX_5);
        else if constexpr (_FreqDivider::num == 14) return std::make_pair(ID__2, TAIDEX_6);
        else if constexpr (_FreqDivider::num == 16) return std::make_pair(ID__2, TAIDEX_7);
        
        else if constexpr (_FreqDivider::num == 20) return std::make_pair(ID__4, TAIDEX_4);
        else if constexpr (_FreqDivider::num == 24) return std::make_pair(ID__4, TAIDEX_5);
        else if constexpr (_FreqDivider::num == 28) return std::make_pair(ID__4, TAIDEX_6);
        else if constexpr (_FreqDivider::num == 32) return std::make_pair(ID__4, TAIDEX_7);
        
        else if constexpr (_FreqDivider::num == 40) return std::make_pair(ID__8, TAIDEX_4);
        else if constexpr (_FreqDivider::num == 48) return std::make_pair(ID__8, TAIDEX_5);
        else if constexpr (_FreqDivider::num == 56) return std::make_pair(ID__8, TAIDEX_6);
        else if constexpr (_FreqDivider::num == 64) return std::make_pair(ID__8, TAIDEX_7);
        else                                        static_assert(Toastbox::AlwaysFalse<_FreqDivider>);
        
        
        
        
    }
};
