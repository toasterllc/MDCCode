#pragma once
#include <msp430.h>
#include <ratio>
#include <limits>
#include "chrono.h" // Local version of <chrono> header
#include "Clock.h"
#include "Assert.h"
#include "Toastbox/Util.h"

// T_Timer: a one-shot timer that can be scheduled for times in the near future
// to distant future (up to ~4 years -- 0xFFFF*T_RTC::InterruptIntervalUs).
//
// T_Timer is implemented to be as low-power as possible by reusing RTC
// wakeups for tracking time over long periods, and then using Timer_A
// for the remainder before the scheduled time.
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
    using Tocks = std::chrono::duration<uint64_t, TocksPeriod>;
    using Tocks16 = std::chrono::duration<uint16_t, TocksPeriod>;
    
    static constexpr Tocks TimerIntervalTocks(0x10000); // Use max interval possible (0xFFFF+1)
    static constexpr Ticks16 TimerIntervalTicks(std::chrono::duration_cast<Ticks16>(TimerIntervalTocks));
    static_assert(Tocks(TimerIntervalTicks) == TimerIntervalTocks); // Verify that conversion is exact
    static_assert(TimerIntervalTicks.count() == 2048); // Debug
    
//    using TimerIntervalSec = std::ratio_divide<std::ratio<TimerIntervalTocks>, TocksFreq>
//    static_assert(TimerIntervalSec::num == 128); // Debug
//    static_assert(TimerIntervalSec::den == 1); // Verify TimerIntervalSec is an integer
//    using TimerIntervalTicks = std::ratio_multiply<TimerIntervalSec, Time::TicksFreq>;
//    static_assert(TimerIntervalTicks::num == 2048); // Debug
//    static_assert(TimerIntervalTicks::den == 1); // Verify that TimerIntervalTicks is an integer
//    
//    static constexpr Ticks TimerIntervalTicks(std::chrono::duration_cast<Ticks>());
//    static_assert();
//    
//    using TicksPerTockRatio = std::ratio<Time::TicksFreqHz, TocksFreq>;
//    static_assert(TicksPerTockRatio::num == 1); // Debug
//    static_assert(TicksPerTockRatio::den == 32); // Debug
    
    static void Schedule(const Clock::Instant& time) {
        // Get our current time
        const Clock::Instant now = T_RTC::Now();
        
        // Disable interrupts while we modify our state
        Toastbox::IntState ints(false);
        
        // Reset our state
        _Reset();
        
        // Make sure scheduled time is in the future
        if (time >= now) {
            const Clock::Ticks16 rtcTimeUntilOverflow = T_RTC::TimeUntilOverflow();
            uint16_t rtcCount = 0;
            Clock::Ticks32 deltaTicks = time-now;
            
            if (deltaTicks >= rtcTimeUntilOverflow) {
                rtcCount = 1;
                deltaTicks -= rtcTimeUntilOverflow;
            }
            
            if (deltaTicks >= T_RTC::InterruptIntervalTicks) {
                const uint16_t count = deltaTicks / T_RTC::InterruptIntervalTicks;
                constexpr uint16_t CountMax = std::numeric_limits<decltype(count)>::max();
                // Verify that our `count` division can't overflow
                Assert(deltaTicks <= CountMax * T_RTC::InterruptIntervalTicks); 
                rtcCount += count;
                deltaTicks -= count*T_RTC::InterruptIntervalTicks;
            }
            
            #warning TODO: add all these static_assert checks back
            // Ensure that `deltaTicks` can be cast to a u32, which we want to do so we don't perform a u64 division
//            constexpr auto DeltaTicksMax = T_RTC::InterruptIntervalTicks-1;
//            static_assert(DeltaTicksMax <= std::numeric_limits<uint32_t>::max());
            const uint16_t intervalCount = deltaTicks / TimerIntervalTicks;
//            // Ensure that `intervalCount` can't overflow
//            constexpr auto IntervalCountMax = ((uintmax_t)DeltaTicksMax / TimerIntervalTicks.count());
//            static_assert(IntervalCountMax <= std::numeric_limits<decltype(intervalCount)>::max());
            
            const Ticks16 remainderTicks = deltaTicks % TimerIntervalTicks;
//            // Ensure that `remainderTicks` can't overflow
//            constexpr auto RemainderTicksMax = TimerIntervalTicks-1;
//            static_assert(RemainderTicksMax <= std::numeric_limits<decltype(remainderTicks)>::max());
            
            #warning TODO: make sure to add this check back too!
//            const Tocks16 remainderTocks = _TocksForTicks<RemainderTicksMax>(remainderTicks);
            const Tocks16 remainderTocks(remainderTicks);
            
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
        return tocks.count()-1;
    }
    
//    template<Ticks T_MaxVal>
//    static constexpr Tocks _TocksForTicks(Ticks ticks) {
//        // Confirm that all values from [0,T_MaxVal] can be safely converted to Tocks
//        static_assert(std::chrono::duration_cast<Ticks>(Tocks(T_MaxVal)) == ticks);
//        return ticks;
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
            Tocks16 remainderTocks = 0;
        } timer;
        
        _State state = _State::Idle;
    } _ISRState;
};
