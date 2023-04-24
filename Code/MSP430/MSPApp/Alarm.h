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
        
        // Disable interrupts while we modify our state
        Toastbox::IntState ints(false);
        
        #warning TODO: ISRTimer() / ISRRTC() could be called within TimeRead()!
        const Time::Instant now = T_RTC::TimeRead();
        
        // Reset our state
        _ISRState = {};
        
        // Handle the alarm time having passed
        if (alarm < now) {
            _ISRState.triggered = true;
            return;
        }
        
        const Time::Us rtcTimeUntilOverflow = T_RTC::TimeUntilOverflow();
        Time::Us deltaUs = alarm-now;
        
        if (deltaUs >= rtcTimeUntilOverflow) {
            _ISRState.rtcCount = 1;
            deltaUs -= rtcTimeUntilOverflow;
        }
        
        if (deltaUs >= T_RTC::InterruptIntervalUs) {
            const uint16_t count = deltaUs / T_RTC::InterruptIntervalUs;
            _ISRState.rtcCount += count;
            deltaUs -= count*T_RTC::InterruptIntervalUs;
        }
        
        // Ensure that `deltaUs` can be cast to a u32, which we want to do so we don't perform a u64 division
        constexpr auto DeltaUsMax = T_RTC::InterruptIntervalUs-1;
        static_assert(DeltaUsMax <= std::numeric_limits<uint32_t>::max());
        const uint16_t intervalCount = (uint32_t)deltaUs / TimerMaxIntervalUs;
        // Ensure that `intervalCount` can't overflow
        constexpr auto IntervalCountMax = ((uintmax_t)DeltaUsMax / (uintmax_t)TimerMaxIntervalUs);
        static_assert(IntervalCountMax <= std::numeric_limits<decltype(intervalCount)>::max());
        
        const uint32_t remainderUs = deltaUs % TimerMaxIntervalUs;
        // Ensure that `remainderUs` can't overflow
        constexpr auto RemainderUsMax = TimerMaxIntervalUs-1;
        static_assert(RemainderUsMax <= std::numeric_limits<decltype(remainderUs)>::max());
        
        const uint16_t remainderCount = (remainderUs * (uint16_t)TimerPeriodUsRatio::den) / (uint16_t)TimerPeriodUsRatio::num;
        // Ensure that `remainderCount` can't overflow
        constexpr auto RemainderCountMax = (RemainderUsMax * TimerPeriodUsRatio::den) / TimerPeriodUsRatio::num;
        static_assert(RemainderCountMax <= std::numeric_limits<decltype(remainderCount)>::max());
        
        _ISRState.timerIntervalCount = intervalCount;
        _ISRState.timerRemainderCount = remainderCount;
        
        _TimerUpdate();
    }
    
    static bool Get() {
        return _Triggered;
    }
    
    static void ISRRTC() {
        // Short-circuit if we're not waiting for RTC interrupts
        if (!_ISRState.rtcCount) return;
        _ISRState.rtcCount--;
        if (_ISRState.rtcCount == 0) {
            _TimerUpdate();
        }
    }
    
    static void ISRTimer() {
        Assert(!_Triggered);
        _Triggered = true;
    }
    
private:
    static void _TimerUpdate() {
        // Stop timer
        TA0CTL = (TA0CTL & ~MC_3) | MC__STOP;
        
        TA0CCR0 = ;
        
        // Configure timer
        TA0CTL =
            TASSEL_1    |   // source = ACLK
            MC__UP      |   // mode = up (count from 0 to TA0CCR0 repeatedly)
            TACLR       |   // reset timer internal state (counter, clock divider state, count direction)
            TAIE        ;   // enable interrupt
    }
    
    static inline volatile struct {
        uint16_t rtcCount = 0;
        uint16_t timerIntervalCount = 0;
        uint16_t timerRemainderCount = 0;
        bool triggered = false;
    } _ISRState;
    
//    static inline volatile Time::Instant _AlarmTime = 0;
//    static inline volatile uint16_t _RTCCount = 0;
//    static inline volatile uint16_t _TimerIntervalCount = 0;
//    static inline volatile uint16_t _TimerRemainderCount = 0;
//    static inline volatile bool _Triggered = false;
};
