#pragma once
#include <msp430.h>
#include <ratio>
#include <limits>
#include "Time.h"

template <typename T_RTC, uint32_t T_ACLKFreqHz>
class T_Alarm {
public:
    static void Set(const Time::Instant& alarm) {
        static constexpr uint32_t TimerACLKDivider = 64;
        
        using TimerFreqHzRatio = std::ratio<T_ACLKFreqHz, TimerACLKDivider>;
        static_assert(TimerFreqHzRatio::den == 1); // Verify TimerFreqHzRatio division is exact
        static constexpr TimerFreqHz = TimerFreqHzRatio::num;
        
        static constexpr uint16_t TimerMaxCCR0 = 0xFFFF;
        using TimerMaxIntervalSecRatio = std::ratio<(uint32_t)TimerMaxCCR0+1, TimerFreqHz>;
        static_assert(TimerMaxIntervalSecRatio::den == 1); // Verify TimerMaxIntervalSecRatio division is exact
        static constexpr uint32_t TimerMaxIntervalSec = TimerMaxIntervalSecRatio::num;
        static constexpr uint32_t TimerMaxIntervalUs  = TimerMaxIntervalSec*1000000;
        
        using TimerPeriodUsRatio = std::ratio<1000000, TimerFreqHz>;
        
        const Time::Instant now = T_RTC::TimeRead();
        
        // Disable interrupts while we modify our state
        Toastbox::IntState ints(false);
        
        if (alarm < now) {
            // Alarm is in past
            ...
            return;
        }
        
        const Time::Us deltaUs = alarm-now;
        if (deltaUs >= T_RTC::InterruptIntervalUs) {
            _RTCCount = deltaUs / T_RTC::InterruptIntervalUs;
            _TimerIntervalCount = 0;
            _TimerRemainderCount = 0;
        
        } else {
            const uint16_t intervalCount = deltaUs / TimerMaxIntervalUs;
            // Ensure that `intervalCount` can't overflow
            constexpr auto IntervalCountMax = ((uintmax_t)T_RTC::InterruptIntervalUs-1 / (uintmax_t)TimerMaxIntervalUs);
            static_assert(IntervalCountMax <= std::numeric_limits<decltype(intervalCount)>::max());
            
            const uint32_t remainderUs = deltaUs % TimerMaxIntervalUs;
            // Ensure that `remainderUs` can't overflow
            constexpr auto RemainderUsMax = TimerMaxIntervalUs-1;
            static_assert(RemainderUsMax <= std::numeric_limits<decltype(remainderUs)>::max());
            
            const uint16_t remainderCount = (remainderUs * (uint16_t)TimerPeriodUsRatio::den) / TimerPeriodUsRatio::num;
            // Ensure that `remainderCount` can't overflow
            constexpr auto RemainderCountMax = (RemainderUsMax * TimerPeriodUsRatio::den) / TimerPeriodUsRatio::num;
            static_assert(RemainderCountMax <= std::numeric_limits<decltype(remainderCount)>::max());
            
            _RTCCount = 0;
            _TimerIntervalCount = intervalCount;
            _TimerRemainderCount = remainderCount;
            
            
            _ISRTimerCount = deltaUs / XXX;
            
            
            2048000000 /
        }
        
        
        if (alarm > now) {
            
        }
        
        if (alarm) {
            
        } else if () {
            
        } else () {
            
        }
        
        _Triggered = false;
        
        
        
        
        
        
        // Stop timer
        TA0CTL = (TA0CTL & ~MC_3) | MC__STOP;
        
        // Configure timer
        TA0CTL =
            TASSEL_1    |   // source = ACLK
            MC__UP      |   // mode = up (count from 0 to TA0CCR0 repeatedly)
            TACLR       |   // reset timer internal state (counter, clock divider state, count direction)
            TAIE        ;   // enable interrupt
        
        TA0CCR0 = ;
        
        
        
        
        
    }
    
    static bool Get() {
        return _Triggered;
    }
    
    static void ISRTimer() {
        Assert(!_Triggered);
        _Triggered = true;
    }
    
    static void ISRRTC() {
        Assert(!_Triggered);
        _Triggered = true;
    }
    
private:
    static inline volatile uint16_t _RTCCount = 0;
    static inline volatile uint16_t _TimerIntervalCount = 0;
    static inline volatile uint16_t _TimerRemainderCount = 0;
    static inline volatile bool _Triggered = false;
};
