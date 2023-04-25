#pragma once
#include <msp430.h>
#include <ratio>
#include <limits>
#include "Time.h"
#include "Assert.h"

template <typename T_RTC, uint32_t T_ACLKFreqHz>
class T_Alarm {
public:
    static constexpr uint32_t TimerACLKDivider = 64;
    
    using TimerFreqHzRatio = std::ratio<T_ACLKFreqHz, TimerACLKDivider>;
    static_assert(TimerFreqHzRatio::den == 1); // Verify TimerFreqHzRatio division is exact
    static constexpr TimerFreqHz = TimerFreqHzRatio::num;
    static_assert(TimerFreqHz == 512); // Debug
    
    static constexpr uint16_t TimerMaxCCR0 = 0xFFFF;
    using TimerMaxIntervalSecRatio = std::ratio<(uint32_t)TimerMaxCCR0+1, TimerFreqHz>;
    static_assert(TimerMaxIntervalSecRatio::den == 1); // Verify TimerMaxIntervalSecRatio division is exact
    static constexpr uint32_t TimerMaxIntervalSec = TimerMaxIntervalSecRatio::num;
    static_assert(TimerMaxIntervalSec == 128); // Debug
    static constexpr uint32_t TimerMaxIntervalUs  = TimerMaxIntervalSec*1000000;
    static_assert(TimerMaxIntervalUs == 128000000); // Debug
    
    using TimerPeriodUsRatio = std::ratio<1000000, TimerFreqHz>;
    static_assert(TimerPeriodUsRatio::num == 15625); // Debug
    static_assert(TimerPeriodUsRatio::den == 8); // Debug
    
    static void Set(const Time::Instant& alarm) {
        // Disable interrupts while we modify our state
        Toastbox::IntState ints(false);
        
        #warning TODO: ISRTimer() / ISRRTC() could be called within TimeRead()!
        const Time::Instant now = T_RTC::TimeRead();
        
        // Reset our state
        _Reset();
        
        if (alarm >= now) {
            const Time::Us rtcTimeUntilOverflow = T_RTC::TimeUntilOverflow();
            uint16_t rtcCount = 0;
            Time::Us deltaUs = alarm-now;
            
            if (deltaUs >= rtcTimeUntilOverflow) {
                rtcCount = 1;
                deltaUs -= rtcTimeUntilOverflow;
            }
            
            if (deltaUs >= T_RTC::InterruptIntervalUs) {
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
    
    static bool Triggered() {
        if (_ISRState.state != _State::Triggered) return false;
        _StateUpdate();
        return true;
    }
    
    static bool ISRRTCInterested() {
        return _ISRState.state == _State::RTCCountdown;
    }
    
    static void ISRRTC() {
        Assert(ISRRTCInterested());
        _StateUpdate();
    }
    
    static void ISRTimer() {
//        switch (_ISRState.state) {
//        case _State::TimerInterval:
//            Assert(_ISRState.timer.intervalCount);
//            _ISRState.timer.intervalCount--;
//            break;
//        
//        case _State::TimerRemainder:
//            Assert(_ISRState.timer.remainderTicks);
//            _ISRState.timer.remainderTicks--;
//            break;
//        
//        default:
//            Assert(false);
//        }
        
        Assert(_ISRState.state==_State::TimerInterval || _ISRState.state==_State::TimerRemainder);
        _StateUpdate();
    }
    
private:
    static void _TimerSet(uint16_t count) {
        const uint16_t mode = (count ? MC__CONTINUOUS : MC__STOP);
        
        // Stop timer
        TA0CTL = (TA0CTL & ~(MC0|MC1)) | MC__STOP;
        
        // Additional clock divider = /8
        TA0EX0 = TAIDEX_7;
        
        if (count) {
            TA0CTL =
                TASSEL__ACLK    |   // clock source = ACLK
                ID__8           |   // clock divider = /8
                MC__CONTINUOUS  |   // mode = continuous
                TACLR           |   // reset timer state
                TAIE            ;   // enable interrupt
        }
    }
    
    // _Reset(): resets the timer and our state (_ISRState)
    // Interrupts must be disabled
    static void _Reset() {
        _ISRState = {};
        _TimerSet(0);
    }
    
    static void _StateUpdate(bool next=false) {
        // Advance to the next state
        if (next) {
            if (_ISRState.state != _State_::Triggered) _ISRState.state++;
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
                    // Set timer
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
                    _TimerSet(TimerMaxCCR0);
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
                    _TimerSet();
                } else {
                    _ISRState.timer.remainderTicks = 0;
                }
            }
            
            if (!_ISRState.timer.remainderTicks) _StateUpdate(true);
            break;
        
        case _State::Triggered:
            break;
        }
    }
    
    using _State = uint8_t;
    struct _State_ { enum : _State {
        Idle,
        RTCCountdown,
        TimerInterval,
        TimerRemainder,
        Triggered,
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
    
//    static inline volatile Time::Instant _AlarmTime = 0;
//    static inline volatile uint16_t _RTCCount = 0;
//    static inline volatile uint16_t _TimerIntervalCount = 0;
//    static inline volatile uint16_t _TimerRemainderCount = 0;
//    static inline volatile bool _Triggered = false;
};
