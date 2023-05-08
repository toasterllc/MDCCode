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
template<typename T_Scheduler, typename T_RTC, uint32_t T_ACLKFreqHz>
class T_Timer {
public:
    // TimerACLKFreqDivider: the freq divider that we apply to our timer
    // We choose the maximum value of 64 to stretch the timer to the
    // longest duration possible in order minimize our number of wakes,
    // to save power.
    static constexpr uint32_t TimerACLKFreqDivider = 64;
    
    using Tocks16 = uint16_t;
    using Tocks32 = uint32_t;
    
    using TocksFreq = std::ratio<T_ACLKFreqHz, TimerACLKFreqDivider>;
    static_assert(TocksFreq::num == 512); // Debug
    static_assert(TocksFreq::den == 1); // Verify TocksFreq is an integer
    
    using TicksPerTock = std::ratio_divide<Time::TicksFreq, TocksFreq>;
    static_assert(TicksPerTock::num == 1); // Debug
    static_assert(TicksPerTock::den == 32); // Debug
    
    static constexpr Tocks32 TimerIntervalTocks = 0x10000; // Use max interval possible (0xFFFF+1)
    using TimerIntervalTicks = std::ratio_multiply<std::ratio<TimerIntervalTocks>, TicksPerTock>;
    static_assert(TimerIntervalTicks::num == 2048); // Debug
    static_assert(TimerIntervalTicks::den == 1); // Verify that TimerIntervalTicks is an integer
    
    static void WaitUntilFired() {
        // Disable interrupts while we modify our state
        Toastbox::IntState ints(false);
        
        for (;;) {
            // Consume pending reset
            _State.reset = false;
            
            // Wait until we're scheduled
            T_Scheduler::Wait([] { return (bool)_State.time; });
            
            // Get our remaining ticks until we fire
            Time::Ticks32 deltaTicks = _TicksRemaining(T_RTC::Now());
            
            // Wait for as many full RTC overflow intervals as possible
            _State.rtc.waiting = _RTCMode(deltaTicks);
            if (_State.rtc.waiting) {
                T_Scheduler::Wait([] { return _State.reset || !_State.rtc.waiting; });
                if (_State.reset) continue;
                // Update deltaTicks
                deltaTicks = _TicksRemaining(T_RTC::Now());
            }
            
            // Wait for full timer intervals for the remaining time less than the RTC overflow interval
            {
                // DeltaTicksMax: the max value of `deltaTicks` at this point
                constexpr auto DeltaTicksMax = T_RTC::InterruptIntervalTicks-1;
                // Ensure that casting deltaTicks to Time::Ticks16 is safe
                static_assert(std::in_range<Time::Ticks16>(DeltaTicksMax));
                // Ensure that casting TimerIntervalTicks::num to Time::Ticks16 is safe
                static_assert(std::in_range<Time::Ticks16>(TimerIntervalTicks::num));
                const uint16_t intervalCount = (Time::Ticks16)deltaTicks / (Time::Ticks16)TimerIntervalTicks::num;
                if (intervalCount) {
                    _TimerWait(_CCRForTocks(TimerIntervalTocks), intervalCount);
                    if (_State.reset) continue;
                }
            }
            
            // Wait for remaining time less than a full timer interval
            {
                const Time::Ticks16 remainderTicks = (Time::Ticks16)deltaTicks % (Time::Ticks16)TimerIntervalTicks::num;
                // RemainderTicksMax: max value of remainderTicks at this point
                constexpr auto RemainderTicksMax = TimerIntervalTicks::num-1;
                // Ensure that casting TicksPerTock::num/den to Time::Ticks16 is safe
                static_assert(std::in_range<Time::Ticks16>(TicksPerTock::num));
                static_assert(std::in_range<Time::Ticks16>(TicksPerTock::den));
                // Ensure that our ticks -> tocks calculation can't overflow due to the multiplication
                static_assert(std::in_range<Time::Ticks16>(RemainderTicksMax * TicksPerTock::den));
                const Tocks16 remainderTocks = (remainderTicks * (Time::Ticks16)TicksPerTock::den) / (Time::Ticks16)TicksPerTock::num;
                if (remainderTocks) {
                    _TimerWait(_CCRForTocks(remainderTocks), 1);
                    if (_State.reset) continue;
                }
            }
            
            break;
        }
    }
    
    static void Schedule(const std::optional<Time::Instant>& time) {
        Toastbox::IntState ints(false);
        
        _TimerStop();
        
        _State = {
            .request = {
                .reset = true,
                .time = time,
            },
        };
    }
    
    [[gnu::noinline]]
    static Time::Ticks32 _TicksRemaining(const Time::Instant& now) {
        if (now >= *_State.time) return 0;
        return *_State.time - now;
    }
    
    [[gnu::noinline]]
    static bool _RTCMode(Time::Ticks32 ticks) {
        return ticks >= T_RTC::InterruptIntervalTicks;
    }
    
    [[gnu::noinline]]
    static void _TimerWait(uint16_t ccr, uint16_t count) {
        _State.timer.count = count;
        _TimerSet(ccr);
        T_Scheduler::Wait([] { return _State.reset || !_State.timer.count; });
    }
    
    static bool ISRRTC() {
        if (!_State.rtc.waiting) return false;
        _State.rtc.waiting = _RTCMode(_TicksRemaining(T_RTC::NowBase()));
        // Wake if we exiting RTC mode
        return !_State.rtc.waiting;
    }
    
    static bool ISRTimer(uint16_t iv) {
        switch (iv) {
        case TA0IV_TAIFG:
            Assert(_State.timer.count);
            _State.timer.count--;
            if (!_State.timer.count) {
                // Stop timer
                _TimerStop();
                // Wake ourself
                return true;
            }
            return false;
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
    
    static void _TimerStop() {
        TA0CTL &= ~(MC1|MC0|TAIE);
    }
    
    static void _TimerSet(uint16_t ccr) {
        // Stop timer
        _TimerStop();
        // Additional clock divider = /8
        TA0EX0 = TAIDEX_7;
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
    
    static inline struct {
        struct {
            bool reset = false;
            std::optional<Time::Instant> time;
        } request;
        
        struct {
            bool waiting = false;
        } rtc;
        
        struct {
            uint16_t count = 0;
        } timer;
    } _State;
};
