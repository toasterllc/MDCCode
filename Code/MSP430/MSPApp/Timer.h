#pragma once
#include <msp430.h>
#include <ratio>
#include <limits>
#include "Time.h"
#include "Assert.h"

// T_Timer: a timer that can be set for times in the near future to distant future (up to ~4 years)
template <typename T_RTC, uint32_t T_ACLKFreqHz>
class T_Timer {
public:
    static constexpr uint32_t TimerACLKDivider = 64;
    
    using TimerFreqHzRatio = std::ratio<T_ACLKFreqHz, TimerACLKDivider>;
    static_assert(TimerFreqHzRatio::den == 1); // Verify TimerFreqHzRatio division is exact
    static constexpr TimerFreqHz = TimerFreqHzRatio::num;
    static_assert(TimerFreqHz == 512); // Debug
    
    static constexpr uint32_t TimerMaxTicks = 0x10000;
    using TimerMaxIntervalSecRatio = std::ratio<TimerMaxTicks, TimerFreqHz>;
    static_assert(TimerMaxIntervalSecRatio::den == 1); // Verify TimerMaxIntervalSecRatio division is exact
    static constexpr uint32_t TimerMaxIntervalSec = TimerMaxIntervalSecRatio::num;
    static_assert(TimerMaxIntervalSec == 128); // Debug
    static constexpr uint32_t TimerMaxIntervalUs  = TimerMaxIntervalSec*1000000;
    static_assert(TimerMaxIntervalUs == 128000000); // Debug
    
    using TimerPeriodUsRatio = std::ratio<1000000, TimerFreqHz>;
    static_assert(TimerPeriodUsRatio::num == 15625); // Debug
    static_assert(TimerPeriodUsRatio::den == 8); // Debug
    
    static void Set(const Time::Instant& time) {
        // Get our current time
        const Time::Instant now = T_RTC::TimeRead();
        
        // Disable interrupts while we modify our state
        Toastbox::IntState ints(false);
        
        // Reset our state
        _Reset();
        
        if (time >= now) {
            const Time::Us rtcTimeUntilOverflow = T_RTC::TimeUntilOverflow();
            uint16_t rtcCount = 0;
            Time::Us deltaUs = time-now;
            
            if (deltaUs >= rtcTimeUntilOverflow) {
                rtcCount = 1;
                deltaUs -= rtcTimeUntilOverflow;
            }
            
            if (deltaUs >= T_RTC::InterruptIntervalUs) {
                // Ensure that our `count` division won't overflow
                Assert(deltaUs <= (Time::Us)0xFFFF*T_RTC::InterruptIntervalUs);
                const uint16_t count = deltaUs / T_RTC::InterruptIntervalUs;
                rtcCount += count;
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
            
            const uint16_t remainderTicks = (remainderUs * (uint16_t)TimerPeriodUsRatio::den) / (uint16_t)TimerPeriodUsRatio::num;
            // Ensure that `remainderTicks` can't overflow
            constexpr auto RemainderTicksMax = (RemainderUsMax * TimerPeriodUsRatio::den) / TimerPeriodUsRatio::num;
            static_assert(RemainderTicksMax <= std::numeric_limits<decltype(remainderTicks)>::max());
            
            _ISRState = {
                .rtc = {
                    .count = rtcCount,
                },
                .timer = {
                    .intervalCount = intervalCount,
                    .remainderTicks = remainderTicks,
                },
            };
        }
        
        _StateUpdate(true);
    }
    
    static bool Fired() {
        if (_ISRState.state != _State::Fired) return false;
        _StateUpdate(true);
        return true;
    }
    
    static bool ISRRTCInterested() {
        return _ISRState.state == _State::RTCCountdown;
    }
    
    static bool ISRRTC() {
        Assert(ISRRTCInterested());
        _StateUpdate();
        return _ISRState.state==_State::Fired;
    }
    
    static bool ISRTA0() {
        Assert(_ISRState.state==_State::TimerInterval || _ISRState.state==_State::TimerRemainder);
        _StateUpdate();
        return _ISRState.state==_State::Fired;
    }
    
//    static void ISRTA0CCR0() {
//        Assert(_ISRState.state==_State::TimerRemainder);
//        _StateUpdate();
//    }
    
private:
    static constexpr uint16_t _CCRForTicks(uint32_t ticks) {
        static_assert(ticks > 0);
        static_assert(ticks-1 <= std::numeric_limits<uint16_t>::max());
        return ticks-1;
    }
    
    static void _TimerStop() {
        TA0CTL &= ~(MC1|MC0|TAIE);
    }
    
    static void _TimerSet(uint16_t ccr) {
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
    }
    
    // _Reset(): resets the timer and our state (_ISRState)
    // Interrupts must be disabled
    static void _Reset() {
        _ISRState = {};
        _TimerStop();
    }
    
    static void _StateUpdate(bool next=false) {
        // Advance to the next state
        if (next) {
            if (_ISRState.state != _State_::Fired) _ISRState.state++;
            else _ISRState.state = 0;
        }
        
        // Handle the current state
        switch (_ISRState.state) {
        case _State::Idle:
            break;
        
        case _State::RTCCountdown:
            if (_ISRState.rtc.count) {
                if (next) {
                    // Handle entering this state
                } else {
                    _ISRState.rtc.count--;
                }
            }
            
            if (!_ISRState.rtc.count) _StateUpdate(true);
            break;
        
        case _State::TimerInterval:
            if (_ISRState.timer.intervalCount) {
                if (next) {
                    // Handle entering this state
                    // Set timer
                    _TimerSet(_CCRForTicks(TimerMaxTicks));
                } else {
                    _ISRState.timer.intervalCount--;
                }
            }
            
            if (!_ISRState.timer.intervalCount) _StateUpdate(true);
            break;
        
        case _State::TimerRemainder:
            if (_ISRState.timer.remainderTicks) {
                if (next) {
                    // Handle entering this state
                    // Set timer
                    _TimerSet(_CCRForTicks(_ISRState.timer.remainderTicks));
                } else {
                    _ISRState.timer.remainderTicks = 0;
                }
            }
            
            if (!_ISRState.timer.remainderTicks) _StateUpdate(true);
            break;
        
        case _State::Fired:
            // Clean up
            _TimerStop();
            break;
        }
    }
    
    using _State = uint8_t;
    struct _State_ { enum : _State {
        Idle,
        RTCCountdown,
        TimerInterval,
        TimerRemainder,
        Fired,
    }; };
    
    static inline volatile struct {
        struct {
            uint16_t count = 0;
        } rtc;
        
        struct {
            uint16_t intervalCount = 0;
            uint16_t remainderTicks = 0;
        } timer;
        
        _State state = _State::Idle;
    } _ISRState;
};
