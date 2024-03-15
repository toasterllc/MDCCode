#pragma once
#include <msp430.h>
#include <ratio>
#include <limits>
#include "Code/Lib/Toastbox/Util.h"
#include "Code/Shared/Time.h"
#include "Code/Shared/Assert.h"

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
    static constexpr uint32_t _ACLKFreqDivider = 64;
    
    using _Tocks16 = uint16_t;
    using _Tocks32 = uint32_t;
    
    using _TocksFreq = std::ratio<T_ACLKFreqHz, _ACLKFreqDivider>;
    static_assert(_TocksFreq::num == 512); // Debug
    static_assert(_TocksFreq::den == 1); // Verify _TocksFreq is an integer
    
    using _TicksPerTock = std::ratio_divide<Time::TicksFreq, _TocksFreq>;
    static_assert(_TicksPerTock::num == 1); // Debug
    static_assert(_TicksPerTock::den == 32); // Debug
    
    static constexpr _Tocks32 _TimerIntervalTocks = 0x10000; // Use max interval possible (0xFFFF+1)
    using _TimerIntervalTicks = std::ratio_multiply<std::ratio<_TimerIntervalTocks>, _TicksPerTock>;
    static_assert(_TimerIntervalTicks::num == 2048); // Debug
    static_assert(_TimerIntervalTicks::den == 1); // Verify that _TimerIntervalTicks is an integer
    
    // Schedule(): sets the time that the timer should fire
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
    
    // Wait(): waits until the timer fires
    // Returns whether we actually waited (true), or the timer fired immediately (false)
    static void Wait() {
        // Disable interrupts while we modify our state
        Toastbox::IntState ints(false);
        
        for (;;) {
            // Wait until we get a request with a valid time
            T_Scheduler::Wait([] { return _State.request.reset && _State.request.time; });
            
            // Consume pending reset
            _State.request.reset = false;
            
            // Get our remaining ticks until we fire
            Time::TicksU32 deltaTicks = _TicksRemaining(T_RTC::Now());
            
            // Short-circuit if we're not waiting
            if (!deltaTicks) return;
            
            // Wait for as many full RTC overflow intervals as possible
            _State.rtc.waiting = _RTCMode(deltaTicks);
            if (_State.rtc.waiting) {
                T_Scheduler::Wait([] { return _State.request.reset || !_State.rtc.waiting; });
                if (_State.request.reset) continue;
                // Update deltaTicks
                deltaTicks = _TicksRemaining(T_RTC::Now());
            }
            
            // Wait for full timer intervals for the remaining time less than the RTC overflow interval
            {
                // DeltaTicksMax: the max value of `deltaTicks` at this point
                constexpr auto DeltaTicksMax = T_RTC::InterruptIntervalTicks-1;
                // Ensure that casting deltaTicks to Time::TicksU16 is safe
                static_assert(std::in_range<Time::TicksU16>(DeltaTicksMax));
                // Ensure that casting _TimerIntervalTicks::num to Time::TicksU16 is safe
                static_assert(std::in_range<Time::TicksU16>(_TimerIntervalTicks::num));
                const uint16_t intervalCount = (Time::TicksU16)deltaTicks / (Time::TicksU16)_TimerIntervalTicks::num;
                if (intervalCount) {
                    _TimerWait(_CCRForTocks(_TimerIntervalTocks), intervalCount);
                    if (_State.request.reset) continue;
                }
            }
            
            // Wait for remaining time less than a full timer interval
            {
                const Time::TicksU16 remainderTicks = (Time::TicksU16)deltaTicks % (Time::TicksU16)_TimerIntervalTicks::num;
                // RemainderTicksMax: max value of remainderTicks at this point
                constexpr auto RemainderTicksMax = _TimerIntervalTicks::num-1;
                // Ensure that casting _TicksPerTock::num/den to Time::TicksU16 is safe
                static_assert(std::in_range<Time::TicksU16>(_TicksPerTock::num));
                static_assert(std::in_range<Time::TicksU16>(_TicksPerTock::den));
                // Ensure that our ticks -> tocks calculation can't overflow due to the multiplication
                static_assert(std::in_range<Time::TicksU16>(RemainderTicksMax * _TicksPerTock::den));
                const _Tocks16 remainderTocks = (remainderTicks * (Time::TicksU16)_TicksPerTock::den) / (Time::TicksU16)_TicksPerTock::num;
                if (remainderTocks) {
                    _TimerWait(_CCRForTocks(remainderTocks), 1);
                    if (_State.request.reset) continue;
                }
            }
        }
    }
    
    static bool ISRRTC() {
        if (!_State.rtc.waiting) return false;
        _State.rtc.waiting = _RTCMode(_TicksRemaining(T_RTC::NowBase()));
        // Wake if we exiting RTC mode
        return !_State.rtc.waiting;
    }
    
    static bool ISRTimer(uint16_t iv) {
        switch (iv) {
        case TA2IV_TAIFG:
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
        TA2CTL &= ~(MC1|MC0|TAIE);
    }
    
    static void _TimerSet(uint16_t ccr) {
        // Stop timer
        _TimerStop();
        // Additional clock divider = /8
        TA2EX0 = TAIDEX_7;
        // Set value to count to
        TA2CCR0 = ccr;
        // Start timer
        TA2CTL =
            TASSEL__ACLK    |   // clock source = ACLK
            ID__8           |   // clock divider = /8
            MC__UP          |   // mode = up
            TACLR           |   // reset timer state
            TAIE            ;   // enable interrupt
    }
    
    [[gnu::noinline]]
    static Time::TicksU32 _TicksRemaining(const Time::Instant& now) {
        if (now >= *_State.request.time) return 0;
        return *_State.request.time - now;
    }
    
    [[gnu::noinline]]
    static bool _RTCMode(Time::TicksU32 ticks) {
        return ticks >= T_RTC::InterruptIntervalTicks;
    }
    
    [[gnu::noinline]]
    static void _TimerWait(uint16_t ccr, uint16_t count) {
        _State.timer.count = count;
        _TimerSet(ccr);
        T_Scheduler::Wait([] { return _State.request.reset || !_State.timer.count; });
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
