#pragma once
#include <msp430.h>
#include "Time.h"

template <typename T_RTC, uint32_t T_ACLKFreqHz>
class T_Alarm {
public:
    static void Set(const Time::Instant& alarm) {
        static constexpr uint32_t TimerACLKDivider = 64;
        static constexpr uint32_t TimerFreqHz = T_ACLKFreqHz / TimerACLKDivider;
        static_assert((T_ACLKFreqHz % TimerACLKDivider) == 0); // Ensure that TimerFreqHz division is exact
        
        // TimerPeriodUs: the period between timer counter increments.
        // TimerPeriodUs isn't exact! We'd need to represent TimerPeriodUs in nanoseconds
        // for it to be exact, which would require a 64-bit division in our calculation
        // of `remainderUs`, which we want to avoid.
        // This non-exact representation costs us up to 10ms of timer error:
        //
        //  TimerCountsApprox = (TimerMaxIntervalUs / floor(1000000/TimerFreqHz))
        //                    = 65540.1945724526
        //   TimerCountsExact = (TimerMaxIntervalUs /      (1000000/TimerFreqHz))
        //                    = 65536
        //             ErrSec = ceil(TimerCountsApprox - TimerCountsExact) * (1/TimerFreqHz)
        //                    = ceil(65540.195 - 65536) * (1/512)
        //                    = 0.0098
        static constexpr uint32_t TimerPeriodUs = 1000000 / TimerFreqHz;
        
        static constexpr uint16_t TimerMaxCCR0 = 0xFFFF;
        static constexpr uint32_t TimerMaxIntervalSec = ((uint32_t)TimerMaxCCR0+1) / TimerFreqHz;
        static_assert((((uint32_t)TimerMaxCCR0+1) % TimerFreqHz) == 0); // Ensure that TimerMaxIntervalSec division is exact
        static constexpr uint32_t TimerMaxIntervalUs = TimerMaxIntervalSec*1000000;
        
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
            _ISRRTCCount = deltaUs / T_RTC::InterruptIntervalUs;
        
        } else {
            const uint16_t intervalCount = deltaUs / TimerMaxIntervalUs;
            const uint16_t remainderUs = deltaUs % TimerMaxIntervalUs;
            const uint16_t remainderCount = remainderUs / TimerPeriodUs;
            
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
    static inline volatile uint16_t _ISRRTCCount = 0;
    static inline volatile uint16_t _ISRTimerCount = 0;
    static inline volatile bool _Triggered = false;
};
