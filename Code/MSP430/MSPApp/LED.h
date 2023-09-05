#pragma once
#include <msp430.h>
#include "Toastbox/Util.h"

template<
typename T_SelectPin,
typename T_SignalPin,
uint32_t T_ACLKFreqHz,
uint32_t T_PeriodMs,
uint32_t T_OnDurationMs
>
struct T_LED {
    using _SignalInactivePin = typename T_SignalPin::template Opts<GPIO::Option::Output1>;
    using _SignalActivePin = typename T_SignalPin::template Opts<GPIO::Option::Output1, GPIO::Option::Sel10>;
    
    struct Pin {
        using SelectPin = typename T_SelectPin::template Opts<GPIO::Option::Output0>;
        using SignalPin = _SignalInactivePin;
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
    static constexpr State StateRed     = 1<<0;
    static constexpr State StateGreen   = 1<<1;
    static constexpr State StateDim     = 1<<2;
    static constexpr State StateFlash   = 1<<3; // Flash once
    static constexpr State StateFlicker = 1<<4; // Flicker every 5s
    
    static bool _On(State x) {
        return x & (StateRed | StateGreen);
    }
    
    static bool _Constant(State x) {
        return !(x & (StateFlash | StateFlicker));
    }
    
    enum class __State {
        Off,
        Dim,
        On,
    };
    
    static void _Set(__State x) {
        constexpr uint16_t StepCount = 256;
        
//        TA0CTL &= ~(MC1|MC0);
        
        // Configure timer
        TA0CTL =
            TASSEL__ACLK    |   // clock source = ACLK
            ID__1           |   // clock divider = /1
            TACLR           ;   // reset timer state
        
        // Additional clock divider = /1
        TA0EX0 = TAIDEX_0;
        // TA0CCR1 = value that causes LED to turn on
        TA0CCR1 = StepCount;
        // TA0CCR0 = value that causes LED to turn off
        TA0CCR0 = StepCount-1;
        // Output mode:
        //   on == true/fade in: set/reset
        //   on == false/fade out: reset/set
        TA0CCTL1 = OUTMOD_3;
//        TA0CCTL1 = (x==__State::Off ? OUTMOD_7 : OUTMOD_3);
//        TA0CCTL1 = OUTMOD_3;//(x==__State::Off ? OUTMOD_7 : OUTMOD_3);
        // Start timer
        TA0CTL |= MC__UP;
        
        if (x == __State::Dim) {
            TA0CCR1 = 0;
            _Scheduler::Sleep(_Scheduler::Ms<1000>);
            
            for (uint16_t i=0; i<=64; i++) {
                TA0CCR1 = i;
                _Scheduler::Sleep(_Scheduler::Ms<8>);
            }
        
        } else {
//            for (int16_t i=64; i>=0; i--) {
//                TA0CCR1 = i;
//                _Scheduler::Sleep(_Scheduler::Ms<8>);
//            }
            
            TA0CCR1 = 256-64;
            _Scheduler::Sleep(_Scheduler::Ms<1000>);
            
            for (uint16_t i=256-64; i<=256; i++) {
                TA0CCR1 = i;
                _Scheduler::Sleep(_Scheduler::Ms<8>);
            }
            
            
//            for (int16_t i=64; i>=0; i--) {
//                TA0CCR1 = i;
//                _Scheduler::Sleep(_Scheduler::Ms<8>);
//            }
            
            
            
//            for (uint16_t i=0; i<=64; i++) {
//                TA0CCR1 = i;
//                _Scheduler::Sleep(_Scheduler::Ms<8>);
//            }
            
            
//            for (uint16_t i=0; i<=256; i++) {
//                TA0CCR1 = i;
//                _Scheduler::Sleep(_Scheduler::Ms<2>);
//            }
        }
        
        
//        if (x == __State::Dim) {
//            for (uint16_t i=0; i<=StepCount/16; i++) {
//                TA0CCR1 = i;
//                _Scheduler::Sleep(_Scheduler::Ms<4>);
//            }
//        
//        } else {
//            for (uint16_t i=0; i<=StepCount; i++) {
//                TA0CCR1 = i;
//                _Scheduler::Sleep(_Scheduler::Ms<4>);
//            }
//        }
    }
    
    static void StateSet(State x) {
        _State = x;
        Pin::SelectPin::Write(_State & StateRed);
        
        _SignalActivePin::template Init<_SignalInactivePin>();
        
        _Set(x & StateDim ? __State::Dim : __State::Off);
        
        
        
        
        
        
        
//        // Fade out LED if needed
//        if (_On(x) && _Constant(x)) {
//            _Set(__State::Off);
//        }
//        
//        _State = x;
//        Pin::SelectPin::Write(_State & StateRed);
//        
//        if (_On(x)) {
//            _SignalActivePin::template Init<_SignalInactivePin>();
//            
//            if (_State & StateFlash) {
//                
//            
//            } else if (_State & StateFlicker) {
//                
//            
//            } else if (_State & StateDim) {
//                _Set(__State::Dim);
//            
//            } else {
//                _Set(__State::On);
//            }
//        
//        } else {
//            // Off
//            
//            // Stop the timer and mask the interrupt
//            // Masking the interrupt seems like a better idea than clearing TAIFG, in case
//            // there's a race between us clearing TAIFG + stopping the timer, and a
//            // an incoming TAIFG=1.
//            TA0CTL &= ~(MC1|MC0);
//            
//            _SignalInactivePin::template Init<_SignalActivePin>();
//        }
//        
//        if (x) {
//            // Configure timer
//            TA0CTL =
//                TASSEL__ACLK    |   // clock source = ACLK
//                ID__1           |   // clock divider = /1
//                TACLR           ;   // reset timer state
//            
//            // Additional clock divider = /3
//            TA0EX0 = _TAIDEX<_ACLKFreqDivider>();
//            // TA0CCR1 = value that causes LED to turn on
//            TA0CCR1 = _TA0CCR1;
//            // TA0CCR0 = value that causes LED to turn off
//            TA0CCR0 = _TA0CCR0;
//            // Set the timer's initial value
//            // This is necessary because the timer always starts driving the output as a 0 (ie LED on), and there
//            // doesn't seem to be a way to set the timer's initial output to 1 instead (ie LED off). So instead we
//            // just start the timer at the instant that it flashes, so it'll flash and then immediately turn off.
//            TA0R = _TA0CCR1;
//            // Output mode = reset/set
//            //   LED on when hitting TA0CCR1
//            //   LED off when hitting TA0CCR0
//            TA0CCTL1 = OUTMOD_7;
//            // Start timer
//            TA0CTL |= MC__UP;
//            
//            // Configure pin to be controlled by timer
//            _PinEnabled::template Init<_PinDisabled>();
//        
//        } else {
//            // Return pin to manual control
//            _PinDisabled::template Init<_PinEnabled>();
//            // Stop the timer and mask the interrupt
//            // Masking the interrupt seems like a better idea than clearing TAIFG, in case
//            // there's a race between us clearing TAIFG + stopping the timer, and a
//            // an incoming TAIFG=1.
//            TA0CTL &= ~(MC1|MC0);
//        }
    }
    
    static State StateGet() {
        return _State;
    }
    
    static inline State _State = 0;
};
