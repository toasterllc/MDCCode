#pragma once
#include <msp430.h>
#include "Toastbox/Util.h"

template<
typename T_Scheduler,
typename T_SelectPin,
typename T_SignalPin,
uint32_t T_ACLKFreqHz,
uint32_t T_PeriodMs,
uint32_t T_OnDurationMs
>
struct T_LED {
    using _SignalInactivePin = typename T_SignalPin::template Opts<GPIO::Option::Output1>;
    using _SignalActivePin = typename T_SignalPin::template Opts<GPIO::Option::Output1, GPIO::Option::Sel10>;
    
    using _SelectGreenPin = typename T_SelectPin::template Opts<GPIO::Option::Output0>;
    using _SelectRedPin = typename T_SelectPin::template Opts<GPIO::Option::Output1>;
    
    struct Pin {
        using Select = _SelectGreenPin;
        using Signal = _SignalInactivePin;
    };
    
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
    
    using State = uint8_t;
    static constexpr State StateOff     = 0;
    static constexpr State StateRed     = 1<<0;
    static constexpr State StateGreen   = 1<<1;
    static constexpr State StateFlicker = 1<<2; // Flicker every 5s
    
    static bool _OnConstant(State x) {
        return x==StateRed || x==StateGreen;
    }
    
    static constexpr int16_t _CountFull = 256;
    static constexpr int16_t _CountOn   = _CountFull/16;
    static constexpr int16_t _CountOff  = 0;
    static constexpr auto _FlashDuration = _Scheduler::Ms<30>;
    
    static int16_t _Count(bool on) {
        return (on ? _CountOn : _CountOff);
    }
    
    static void _Fade(bool on) {
        const int16_t countBegin = _Count(!on);
        const int16_t countEnd = _Count(on);
        const int16_t delta = countEnd>=countBegin ? 1 : -1;
        
        // Configure timer
        TA0CTL =
            TASSEL__ACLK    |   // clock source = ACLK
            ID__1           |   // clock divider = /1
            TACLR           ;   // reset timer state
        
        // Additional clock divider = /1
        TA0EX0 = TAIDEX_0;
        // TA0CCR1 = value that causes LED to turn on
        TA0CCR1 = _CountFull;
        // TA0CCR0 = value that causes LED to turn off
        TA0CCR0 = _CountFull-1;
        // Output mode:
        //   on == true/fade in: set/reset
        //   on == false/fade out: reset/set
        TA0CCTL1 = OUTMOD_3;
        // Start timer
        TA0CTL |= MC__UP;
        
        TA0R = _CountFull/4;
        
        for (int16_t i=countBegin;; i+=delta) {
            TA0CCR1 = i;
            T_Scheduler::Sleep(_Scheduler::Ms<16>);
            if (i == countEnd) break;
        }
    }
    
    static void _PinsConfig(State x) {
        if (x & StateGreen) _SelectGreenPin::template Init<_SelectRedPin>();
        else                _SelectRedPin::template Init<_SelectGreenPin>();
        
        if (x == StateOff) _SignalInactivePin::template Init<_SignalActivePin>();
        else               _SignalActivePin::template Init<_SignalInactivePin>();
    }
    
    static void Flash() {
        // Take manual control of pins
        _SignalInactivePin::template Init<_SignalActivePin>();
        _SelectGreenPin::template Init<_SelectRedPin>();
        
        _SignalInactivePin::Write(0);
        T_Scheduler::Sleep(_FlashDuration);
        _SignalInactivePin::Write(1);
        
        // Return pins to their previous state
        _PinsConfig(_State);
    }
    
    static void StateSet(State x) {
        // Short-circuit if the state didn't change
        if (x == _State) return;
        
        // Fade LED off if it's on
        if (_OnConstant(_State)) _Fade(false);
        
        _State = x;
        _PinsConfig(_State);
        
        if (_OnConstant(x)) {
            _Fade(true);
        
        } else if (_State & StateFlicker) {
            
        
        } else {
            // Off
            
            // Stop the timer and mask the interrupt
            // Masking the interrupt seems like a better idea than clearing TAIFG, in case
            // there's a race between us clearing TAIFG + stopping the timer, and a
            // an incoming TAIFG=1.
            TA0CTL &= ~(MC1|MC0);
        }
    }
    
    static inline State _State = StateOff;
};
