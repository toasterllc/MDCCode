#pragma once
#include <msp430.h>
#include "Time.h"

template <typename T_RTC>
class T_Alarm {
public:
    static void Set(const Time::Instant& alarm) {
        const Time::Instant now = T_RTC::TimeRead();
        
        // Disable interrupts while we modify our state
        Toastbox::IntState ints(false);
        
        // Stop timer
        TA0CTL = (TA0CTL & ~MC_3) | MC__STOP;
        
        // Configure timer
        TA0CTL =
            TASSEL_1    |   // source = ACLK
            MC__UP      |   // mode = up (count from 0 to TA0CCR0 repeatedly)
            TACLR       |   // reset timer internal state (counter, clock divider state, count direction)
            TAIE        ;   // enable interrupt
        
        TA0CCR0 = ;
        
        if (alarm < now) {
            // Alarm is in past
            ...
            return;
        }
        
        
        
        if (alarm > now) {
            
        }
        
        if (alarm) {
            
        } else if () {
            
        } else () {
            
        }
        
        _Triggered = false;
    }
    
    static bool Get() {
        return _Triggered;
    }
    
    static void ISR() {
        Assert(!_Triggered);
        _Triggered = true;
    }
    
private:
    static inline volatile bool _Triggered = false;
};
