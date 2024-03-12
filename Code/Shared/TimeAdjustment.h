#pragma once
#include "Time.h"
#include "Clock.h"
#include "Code/Shared/MSP.h"
#include "Code/Lib/Toastbox/Cast.h"

namespace Time {

/// AdjustmentCalculate(): calculates the adjustment to `state` to correct it to the
/// current time, and also quantifies the drift over the total elapsed time so that
/// the device can continuously correct its time in the future.
///
/// The return value consists of four values: .value, .counter, .interval, and .delta:
///
///   .value: is the adjustment for the current instant to correct it to the current
///       time.
///
///   .counter: only used by the device; 0 is returned.
///
///   .delta / .interval: corresponds to the drift over the device's total elapsed
///       time, allowing the device to continuously correct its time. This is a ratio
///       which equals the time adjustment per elapsed time, which equals the negative
///       drift per elapsed time.
///
///       .delta is constrained to [1,TicksFreq], thereby capping unadjusted drift to
///       a maximum of one second. (Ie, the raw unadjusted time is allowed to drift up
///       to one second before it's corrected.)
///       The implementation searches for the .delta/.interval fixed-point ratio that's
///       closest to the target floating-point ratio.
static MSP::TimeAdjustment TimeAdjustmentCalculate(const MSP::TimeState& state) {
    assert(Time::Absolute(state.start));
    assert(Time::Absolute(state.time));
    const Time::Clock::time_point nowTime = Time::Clock::now();
    const Time::Instant nowInstant = Time::Clock::TimeInstantFromTimePoint(nowTime);
    const uint64_t drift = std::max(nowInstant, state.time) - std::min(nowInstant, state.time);
    // Short-circuit if there's 0-2 ticks of drift, since that could just be noise
    if (drift <= 2) return {};
    
    // Require at least `ElapsedHoursMin` of data before we institute an adjustment
    {
        constexpr std::chrono::hours ElapsedHoursMin(12);
        const std::chrono::hours elapsedHours = std::chrono::duration_cast<std::chrono::hours>(nowTime-Time::Clock::TimePointFromTimeInstant(state.start));
        if (elapsedHours < ElapsedHoursMin) return {};
    }
    
    // Verify that the device started tracking time in the past
    if (state.start >= nowInstant) throw Toastbox::RuntimeError("MSP::TimeState.start invalid");
    const Time::TicksU64 elapsed = nowInstant - state.start;
    const double target = (double)drift / elapsed;
    struct {
        uint64_t interval = 0;
        uint64_t delta = 0;
        double err = INFINITY;
    } best;
    
    static_assert(Time::TicksFreq::den == 1); // Check assumption
    for (uint64_t delta=1; delta<=Time::TicksFreq::num; delta++) {
        const uint64_t interval = (elapsed * delta) / drift;
        const double err = std::abs(((double)delta/interval) - target);
        if (err < best.err) {
            best = {
                .interval = interval,
                .delta    = delta,
                .err      = err,
            };
        }
    }
    
    using Value    = decltype(MSP::TimeAdjustment::value);
    using Interval = decltype(MSP::TimeAdjustment::interval);
    using Delta    = decltype(MSP::TimeAdjustment::delta);
    
    const int16_t deltaSign = (nowInstant>=state.time ? 1 : -1);
    return {
        .value    = Toastbox::Cast<Delta>(deltaSign * (int64_t)drift),
        .interval = Toastbox::Cast<Interval>(best.interval),
        .delta    = Toastbox::Cast<Delta>(deltaSign * (int16_t)best.delta),
    };
}

} // namespace Time
