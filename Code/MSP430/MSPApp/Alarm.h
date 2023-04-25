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
    
    static constexpr uint16_t TimerMaxCCR0 = 0xFFFF;
    using TimerMaxIntervalSecRatio = std::ratio<(uint32_t)TimerMaxCCR0+1, TimerFreqHz>;
    static_assert(TimerMaxIntervalSecRatio::den == 1); // Verify TimerMaxIntervalSecRatio division is exact
    static constexpr uint32_t TimerMaxIntervalSec = TimerMaxIntervalSecRatio::num;
    static constexpr uint32_t TimerMaxIntervalUs  = TimerMaxIntervalSec*1000000;
    
    using TimerPeriodUsRatio = std::ratio<1000000, TimerFreqHz>;
    
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
            
            const uint16_t remainderCount = (remainderUs * (uint16_t)TimerPeriodUsRatio::den) / (uint16_t)TimerPeriodUsRatio::num;
            // Ensure that `remainderCount` can't overflow
            constexpr auto RemainderCountMax = (RemainderUsMax * TimerPeriodUsRatio::den) / TimerPeriodUsRatio::num;
            static_assert(RemainderCountMax <= std::numeric_limits<decltype(remainderCount)>::max());
            
            _ISRState = {
                .rtc = {
                    .count = rtcCount,
                },
                .timer = {
                    .intervalCount = intervalCount,
                    .remainderCounter = remainderCount,
                },
            };
        }
        
        _StateNext();
    }
    
//    static bool Triggered() {
//        if (_ISRState.state != _State::Triggered) return false;
//        _NextState();
//        return true;
//    }
    
    static bool ISRRTCInterested() {
        return _ISRState.state == _State::RTCCountdown;
    }
    
    static void ISRRTC() {
        Assert(ISRRTCInterested());
        _StateNext(0);
    }
    
    static void ISRTimer() {
//        switch (_ISRState.state) {
//        case _State::TimerInterval:
//            Assert(_ISRState.timer.intervalCount);
//            _ISRState.timer.intervalCount--;
//            break;
//        
//        case _State::TimerRemainder:
//            Assert(_ISRState.timer.remainderCount);
//            _ISRState.timer.remainderCount--;
//            break;
//        
//        default:
//            Assert(false);
//        }
        
        Assert(_ISRState.state==_State::TimerInterval || _ISRState.state==_State::TimerRemainder);
        _StateNext(0);
    }
    
//    static void ISRTimerRemainder() {
//        Assert(_ISRState.timer.remainderCount);
//        _ISRState.timer.remainderCount--;
//        _StateNext(0);
//    }
    
private:
//    static bool _TimerRunning() {
//        return (TA0CTL & (MC1 | MC0)) != MC__STOP;
//    }
    
    static bool _Done() {
        return !_ISRState.rtc.count && !_ISRState.timer.intervalCount && !_ISRState.timer.remainderCount;
    }
    
    static void _TimerReset() {
        TA0CTL =
            TASSEL__ACLK    |   // clock source = ACLK
            ID__8           |   // clock divider = /8
            MC__STOP        |   // mode = stopped
            TACLR           |   // reset
            TAIE            ;   // enable interrupt
        
        // Additional clock divider = /8
        TA0EX0 = TAIDEX_7;
    }
    
    static void _TimerSet(uint16_t count) {
        switch () {
        
        }
        
        // Additional clock divider = /8
        TA0EX0 = TAIDEX_7;
        
        TA0CTL =
            TASSEL__ACLK    |   // clock source = ACLK
            ID__8           |   // clock divider = /8
            MC__STOP        |   // mode = stopped
            TACLR           |   // reset
            TAIE            ;   // enable interrupt
        
        
        
        
    }
    
    // _Reset(): resets the timer and our state (_ISRState)
    // Interrupts must be disabled
    static void _Reset() {
        _ISRState = {};
        _TimerReset();
    }
    
//    static void _StateIncrement() {
//        // Transition to the new state
//        if (_ISRState.state != _State_::Triggered) _ISRState.state++;
//        else _ISRState.state = 0;
//    }
    
//    static void _StateNext(bool delta=1) {
//        // Add `delta` to the current state
//        if (delta) {
//            if (_ISRState.state != _State_::Triggered) _ISRState.state++;
//            else _ISRState.state = 0;
//        }
//        
//        // Handle the new state
//        switch (_ISRState.state) {
//        case _State::Idle:
//            break;
//        
//        case _State::RTCCountdown:
//            if (_ISRState.rtc.count) {
//                if (delta) {
//                    // Handle entering this state
//                    // Set timer
//                } else {
//                    _ISRState.rtc.count--;
//                    _StateNext();
//                }
//            } else {
//                _StateNext();
//            }
//            break;
//        
//        case _State::TimerInterval:
//            if (_ISRState.timer.intervalCount) {
//                if (delta) {
//                    // Handle entering this state
//                    // Set timer
//                } else {
//                    _ISRState.timer.intervalCount--;
//                    _StateNext();
//                }
//            } else {
//                _StateNext();
//            }
//            break;
//        
//        case _State::TimerRemainder:
//            if (_ISRState.timer.remainderCount) {
//                if (delta) {
//                    // Handle entering this state
//                    // Set timer
//                } else {
//                    _ISRState.timer.remainderCount--;
//                    _StateNext();
//                }
//            } else {
//                _StateNext();
//            }
//            break;
//        
//        case _State::Triggered:
//            break;
//        }
//    }
    
    
    static void _StateNext(bool delta=1) {
        // Add `delta` to the current state
        if (delta) {
            if (_ISRState.state != _State_::Triggered) _ISRState.state++;
            else _ISRState.state = 0;
        }
        
        // Handle the new state
        switch (_ISRState.state) {
        case _State::Idle:
            break;
        
        case _State::RTCCountdown:
            if (_ISRState.rtc.count) {
                if (delta) {
                    // Handle entering this state
                    // Set timer
                } else {
                    _ISRState.rtc.count--;
                    _StateNext(0);
                }
            } else {
                _StateNext();
            }
            break;
        
        case _State::TimerInterval:
            if (_ISRState.timer.intervalCount) {
                if (delta) {
                    // Handle entering this state
                    // Set timer
                } else {
                    _ISRState.timer.intervalCount--;
                    _StateNext(0);
                }
            } else {
                _StateNext();
            }
            break;
        
        case _State::TimerRemainder:
            if (_ISRState.timer.remainderCount) {
                if (delta) {
                    // Handle entering this state
                    // Set timer
                } else {
                    _ISRState.timer.remainderCount--;
                    _StateNext(0);
                }
            } else {
                _StateNext();
            }
            break;
        
        case _State::Triggered:
            break;
        }
    }
    
    
    
    
    
    
    
    
    
    
    
    
    
    
//    static void _StateIncrement() {
//        // Transition to the new state
//        if (_ISRState.state != _State_::Triggered) _ISRState.state++;
//        else _ISRState.state = 0;
//    }
//    
//    static void _StateNext() {
//        switch (_ISRState.state) {
//        case _State::Idle:
//            _StateIncrement();
//            _StateNext();
//            break;
//        case _State::RTCCountdown:
//            if (!_ISRState.rtc.count) {
//                _StateNext();
//            }
//            break;
//        case _State::TimerInterval:
//            if () {
//                
//            }
//            break;
//        case _State::TimerRemainder:
//            break;
//        case _State::Triggered:
//            break;
//        }
//        
//        
//        
//        
//        
//        
//        
//        switch (_ISRState.state) {
//        case _State::Idle:
//            if (_ISRState.rtc.count) {
//                _ISRState.state = _State::RTCCountdown;
//            } else if (_ISRState.timer.intervalCount) {
//                _ISRState.state = _ISRState.timer.intervalCount;
//            } else if (_ISRState.timer.remainderCount) {
//                
//            }
//        case _State::RTCCountdown:
//        case _State::TimerInterval:
//        case _State::TimerRemainder:
//        case _State::Triggered:
//        }
//        
//        
//        #warning TODO: determine if we need a delay after reconfiguring the timer
//        
//        if (_Done()) {
//            _TimerReset();
//            _ISRState.triggered = true;
//        
//        } else if () {
//            
//        }
//        
//        // Stop timer
//        TA0CTL = (TA0CTL & ~MC_3) | MC__STOP;
//        
//        TA0CCR0 = ;
//        
//        // Configure timer
//        TA0CTL =
//            TASSEL_1        |   // source = ACLK
//            MC__CONTINUOUS  |   // mode = continuous (count from 0 to 0xFFFF repeatedly)
//            TACLR           |   // reset timer internal state (counter, clock divider state, count direction)
//            TAIE            ;   // enable interrupt
//    }
    
    using _State = uint8_t;
    struct _State_ { enum : _State {
        Idle,
        RTCCountdown,
        TimerInterval,
        TimerRemainder,
        Triggered,
    }; };
    
    
//    enum class _State : uint8_t {
//        Idle,
//        RTCCountdown,
//        TimerInterval,
//        TimerRemainder,
//        Triggered,
//    };
    
    static inline volatile struct {
        struct {
            uint16_t count = 0;
        } rtc;
        
        struct {
            uint16_t intervalCount = 0;
            uint16_t remainderCount = 0;
        } timer;
        
        _State state = _State::Idle;
    } _ISRState;
    
//    static inline volatile Time::Instant _AlarmTime = 0;
//    static inline volatile uint16_t _RTCCount = 0;
//    static inline volatile uint16_t _TimerIntervalCount = 0;
//    static inline volatile uint16_t _TimerRemainderCount = 0;
//    static inline volatile bool _Triggered = false;
};
