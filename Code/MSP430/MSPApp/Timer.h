#pragma once
#include <msp430.h>
#include <ratio>
#include <limits>
#include "Time.h"
#include "Assert.h"
#include "Toastbox/Util.h"

// T_Timer: a one-shot timer that can be scheduled for times in the near future
// to distant future (up to ~4 years -- 0xFFFF*T_RTC::InterruptIntervalUs).
//
// T_Timer is implemented to be as lower-power as possible by reusing RTC
// wakeups for tracking time over long periods, and then using Timer_A
// for the remaining time after the final RTC wakeup before the scheduled
// time.
template<typename T_RTC, uint32_t T_ACLKFreqHz>
class T_Timer {
public:
    static constexpr uint32_t TimerACLKFreqDivider = 64;
    
    using TocksFreq = std::ratio<T_ACLKFreqHz, TimerACLKFreqDivider>;
    static_assert(TocksFreq::num == 512); // Debug
    static_assert(TocksFreq::den == 1); // Verify TocksFreq is an integer
    using TocksPeriod = std::ratio_divide<std::ratio<1>,TocksFreq>;
    static_assert(TocksPeriod::num == 1); // Debug
    static_assert(TocksPeriod::den == 512); // Debug
    
    static constexpr uint32_t TimerIntervalTocks = 0x10000; // Use max interval possible (0xFFFF+1)
    using TimerIntervalSec = std::ratio_divide<std::ratio<TimerIntervalTocks>, TocksFreq>;
    static_assert(TimerIntervalSec::num == 128); // Debug
    static_assert(TimerIntervalSec::den == 1); // Verify TimerIntervalSec is an integer
    using TimerIntervalTicks = std::ratio_multiply<TimerIntervalSec, Time::TicksFreq>;
    static_assert(TimerIntervalTicks::num == 2048); // Debug
    static_assert(TimerIntervalTicks::den == 1); // Verify that TimerIntervalTicks is an integer
    
    using TicksPerTock = std::ratio_divide<Time::TicksFreq, TocksFreq>;
    static_assert(TicksPerTock::num == 1); // Debug
    static_assert(TicksPerTock::den == 32); // Debug
    
    static void Schedule(const Time::Instant& time) {
        // Get our current time
        const Time::Instant now = T_RTC::Now();
        
        // Disable interrupts while we modify our state
        Toastbox::IntState ints(false);
        
        // Reset our state
        _Reset();
        
        if (time >= now) {
            const uint16_t rtcTicksUntilOverflow = T_RTC::TicksUntilOverflow();
            uint16_t rtcCount = 0;
            const Time::Ticks deltaTicksWide = time-now;
            uint32_t deltaTicks = deltaTicksWide;
            // Ensure that the runtime value of `deltaTicksWide` fits in `deltaTicks`
            Assert(std::in_range<decltype(deltaTicks)>(deltaTicksWide));
//            Assert(deltaTicksWide <= std::numeric_limits<decltype(deltaTicks)>::max()); 
            
            if (deltaTicks >= rtcTicksUntilOverflow) {
                rtcCount = 1;
                deltaTicks -= rtcTicksUntilOverflow;
            }
            
            if (deltaTicks >= T_RTC::InterruptIntervalTicks) {
                // Ensure that the type of T_RTC::InterruptIntervalTicks is a uint16_t, as we expect
                static_assert(std::is_same_v<T_RTC::InterruptIntervalTicks, uint16_t>);
                const uint16_t count = deltaTicks / T_RTC::InterruptIntervalTicks;
                constexpr uint16_t CountMax = std::numeric_limits<decltype(count)>::max();
                // Verify that our `count` division can't overflow
                Assert(deltaTicks <= (Time::Ticks)CountMax * T_RTC::InterruptIntervalTicks); 
                rtcCount += count;
                deltaTicks -= count*T_RTC::InterruptIntervalTicks;
            }
            
            // DeltaTicksMax: the max value of `deltaTicks` at this point
            constexpr auto DeltaTicksMax = T_RTC::InterruptIntervalTicks-1;
            // Ensure that casting deltaTicks to uint16_t is safe
            static_assert(std::in_range<uint16_t>(DeltaTicksMax));
            // Ensure that casting TimerIntervalTicks::num to uint16_t is safe
            static_assert(std::in_range<uint16_t>(TimerIntervalTicks::num));
            const uint16_t intervalCount = (uint16_t)deltaTicks / (uint16_t)TimerIntervalTicks::num;
            const uint16_t remainderTicks = (uint16_t)deltaTicks % (uint16_t)TimerIntervalTicks::num;
            // RemainderTicksMax: max value of remainderTicks at this point
            constexpr auto RemainderTicksMax = TimerIntervalTicks::num-1;
            // Ensure that our ticks -> tocks calculation can't overflow due to the multiplication
            static_assert(std::in_range<uint16_t>(RemainderTicksMax * TicksPerTock::den));
            const uint16_t remainderTocks = (remainderTicks * (uint16_t)TicksPerTock::den) / (uint16_t)TicksPerTock::num;
            
            _ISRState = {
                .rtc = {
                    .count = rtcCount,
                },
                .timer = {
                    .intervalCount = intervalCount,
                    .remainderTocks = remainderTocks,
                },
            };
            
//            _ISRState = {
//                .rtc = {
//                    .count = 1,
//                },
//                .timer = {
//                    .intervalCount = 1,
//                    .remainderTocks = _TocksForTicks<RemainderTicksMax>(7*Time::TicksFreqHz),
//                },
//            };
        }
        
        _StateUpdate();
    }
    
    static bool Fired() {
        Toastbox::IntState ints(false);
        return _ISRState.state == _State::Fired;
    }
    
    static void Reset() {
        Toastbox::IntState ints(false);
        _Reset();
    }
    
    static bool ISRRTCInterested() {
        return _ISRState.state == _State::RTC;
    }
    
    static void ISRRTC() {
        Assert(ISRRTCInterested());
        _StateUpdate();
    }
    
    static void ISRTimer0(uint16_t iv) {
        switch (__even_in_range(iv, TA0IV_TAIFG)) {
        case TA0IV_TAIFG:
            Assert(_ISRState.state==_State::TimerInterval || _ISRState.state==_State::TimerRemainder);
            _StateUpdate();
            return;
        default:
            Assert(false);
        }
    }
    
private:
    // _CCRForTocks(): templated to work with uint16_t (at runtime) and uint32_t (at compile time)
    template<typename T>
    static constexpr uint16_t _CCRForTocks(T tocks) {
        return tocks-1;
    }
    
//    template<auto T_MaxVal, Time::Ticks T_MaxVal>
//    static constexpr uint16_t _TocksForTicks(T_Ticks ticks) {
//        // Verify that our calculation can't overflow assuming a maximum `ticks` value of `T_MaxVal`
//        static_assert(((std::numeric_limits<uint16_t>::max() * TicksPerTockRatio::num) / TicksPerTockRatio::den) <= T_MaxVal);
//        return ((ticks*TicksPerTockRatio::den)/TicksPerTockRatio::num);
//    }
    
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
    
    static void _StateUpdate() {
        for (;;) {
            switch (_ISRState.state) {
            case _State::Idle:
                goto NextState;
            
            case _State::RTCPrepare:
                if (!_ISRState.rtc.count) goto NextState;
                goto NextStateReturn;
            
            case _State::RTC:
                if (_ISRState.rtc.count) _ISRState.rtc.count--;
                if (_ISRState.rtc.count) return;
                goto NextState;
            
            case _State::TimerIntervalPrepare:
                if (!_ISRState.timer.intervalCount) goto NextState;
                _TimerSet(_CCRForTocks(TimerIntervalTocks)); // Set timer
                goto NextStateReturn;
            
            case _State::TimerInterval:
                if (_ISRState.timer.intervalCount) _ISRState.timer.intervalCount--;
                if (_ISRState.timer.intervalCount) return;
                // Cleanup
                _TimerStop();
                goto NextState;
            
            case _State::TimerRemainderPrepare:
                if (!_ISRState.timer.remainderTocks) goto NextState;
                _TimerSet(_CCRForTocks(_ISRState.timer.remainderTocks)); // Set timer
                goto NextStateReturn;
            
            case _State::TimerRemainder:
                // Clean up
                _TimerStop();
                goto NextStateReturn;
            
            case _State::Fired:
                return;
            }
            
            NextState:
                _ISRState.state = (_State)(std::to_underlying(_ISRState.state)+1);
                continue;
            
            NextStateReturn:
                _ISRState.state = (_State)(std::to_underlying(_ISRState.state)+1);
                return;
        }
    }
    
    enum class _State : uint8_t {
        Idle,
        RTCPrepare,
        RTC,
        TimerIntervalPrepare,
        TimerInterval,
        TimerRemainderPrepare,
        TimerRemainder,
        Fired,
    };

    static inline struct {
        struct {
            uint16_t count = 0;
        } rtc;
        
        struct {
            uint16_t intervalCount = 0;
            uint16_t remainderTocks = 0;
        } timer;
        
        _State state = _State::Idle;
    } _ISRState;
};
