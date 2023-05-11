#pragma once
#include <msp430.h>
#include "Toastbox/Util.h"

template<typename T_Pin, uint32_t T_ACLKFreqHz, uint32_t T_PeriodMs, uint32_t T_OnDurationMs>
struct T_LEDFlicker {
    
    using _PinEnabled  = typename T_Pin::template Opts<GPIO::Option::Output1, GPIO::Option::Sel10>;
    using _PinDisabled = typename T_Pin::template Opts<GPIO::Option::Output1>;
    
    using _Tocks32 = uint32_t;
    
    template<_Tocks32 T_Tocks>
    static constexpr uint16_t _CCRForTocks() {
        static_assert(T_Tocks <= _TocksMax);
        return T_Tocks-1;
    }
    
    template<uint8_t T_Divider>
    static constexpr uint16_t _TAIDEX() {
             if constexpr (T_Divider == 1) return TAIDEX_0;
        else if constexpr (T_Divider == 2) return TAIDEX_1;
        else if constexpr (T_Divider == 3) return TAIDEX_2;
        else if constexpr (T_Divider == 4) return TAIDEX_3;
        else if constexpr (T_Divider == 5) return TAIDEX_4;
        else if constexpr (T_Divider == 6) return TAIDEX_5;
        else if constexpr (T_Divider == 7) return TAIDEX_6;
        else if constexpr (T_Divider == 8) return TAIDEX_7;
        else                               static_assert(Toastbox::AlwaysFalse<T_Divider>);
    }
    
    static constexpr _Tocks32 _TocksMax = 0x10000;
    static constexpr uint32_t _ACLKFreqDivider = 3;
    
    using _TocksFreq = std::ratio<T_ACLKFreqHz, _ACLKFreqDivider>;
    using _PeriodTocksRatio = std::ratio_multiply<_TocksFreq, std::ratio<T_PeriodMs,1000>>;
    using _OnDurationTocksRatio = std::ratio_multiply<_TocksFreq, std::ratio<T_OnDurationMs,1000>>;
    
    static constexpr _Tocks32 _PeriodTocks = _PeriodTocksRatio::num / _PeriodTocksRatio::den;
    static constexpr _Tocks32 _OnDurationTocks = _OnDurationTocksRatio::num / _OnDurationTocksRatio::den;
    
    static constexpr uint16_t _TA0CCR0 = _CCRForTocks<_PeriodTocks>();
    static constexpr uint16_t _TA0CCR1 = _CCRForTocks<_PeriodTocks-_OnDurationTocks>();
    
    static void Enabled(bool x) {
        // Short-circuit if our state hasn't changed
        if (x == Enabled()) return;
        
        if (x) {
            // Configure timer
            TA0CTL =
                TASSEL__ACLK    |   // clock source = ACLK
                ID__1           |   // clock divider = /1
                TACLR           ;   // reset timer state
            
            // Additional clock divider = /3
            TA0EX0 = _TAIDEX<_ACLKFreqDivider>();
            // TA0CCR1 = value that causes LED to turn on
            TA0CCR1 = _TA0CCR1;
            // TA0CCR0 = value that causes LED to turn off
            TA0CCR0 = _TA0CCR0;
            // Set the timer's initial value
            // This is necessary because the timer always starts driving the output as a 0 (ie LED on), and there
            // doesn't seem to be a way to set the timer's initial output to 1 instead (ie LED off). So instead we
            // just start the timer at the instant that it flashes, so it'll flash and then immediately turn off.
            TA0R = _TA0CCR1;
            // Output mode = reset/set
            //   LED on when hitting TA0CCR1
            //   LED off when hitting TA0CCR0
            TA0CCTL1 = OUTMOD_7;
            // Start timer
            TA0CTL |= MC__UP;
            
            // Configure pin to be controlled by timer
            _PinEnabled::template Init<_PinDisabled>();
        
        } else {
            // Return pin to manual control
            _PinDisabled::template Init<_PinEnabled>();
            // Stop the timer and mask the interrupt
            // Masking the interrupt seems like a better idea than clearing TAIFG, in case
            // there's a race between us clearing TAIFG + stopping the timer, and a
            // an incoming TAIFG=1.
            TA0CTL &= ~(MC1|MC0);
        }
    }
    
    static bool Enabled() {
        return TA0CTL & (MC1|MC0);
    }
};
