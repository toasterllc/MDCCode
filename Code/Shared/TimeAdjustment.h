#pragma once
#include "Time.h"
#include "Clock.h"
#include "Code/Shared/MSP.h"
#include "Code/Lib/Toastbox/Cast.h"
#include "Code/Lib/Toastbox/DurationString.h"
#include "Code/Lib/Toastbox/RuntimeError.h"

namespace Time {

// AdjustmentCalculate(): calculates the adjustment to `state` to correct it to the
// current time, and also quantifies the drift over the total elapsed time so that
// the device can continuously correct its time in the future.
//
// The return value consists of four values: .value, .counter, .interval, and .delta:
//
//   .value: is the adjustment for the current instant to correct it to the current
//       time.
//
//   .counter: only used by the device; 0 is returned.
//
//   .delta / .interval: corresponds to the drift over the device's total elapsed
//       time, allowing the device to continuously correct its time. This is a ratio
//       which equals the time adjustment per elapsed time, which equals the negative
//       drift per elapsed time.
//
//       .delta is constrained to [1,TicksFreq], thereby capping unadjusted drift to
//       a maximum of one second. (Ie, the raw unadjusted time is allowed to drift up
//       to one second before it's corrected.)
//       The implementation searches for the .delta/.interval fixed-point ratio that's
//       closest to the target floating-point ratio.
//
inline MSP::TimeAdjustment TimeAdjustmentCalculate(const MSP::TimeState& state) {
    assert(Time::Absolute(state.start));
    assert(Time::Absolute(state.time));
    const Time::Clock::time_point nowTime = Time::Clock::now();
    const Time::Clock::time_point deviceStartTime = Time::Clock::TimePointFromTimeInstant(state.start);
    const Time::Clock::time_point deviceNowTime = Time::Clock::TimePointFromTimeInstant(state.time);
    
    // Verify that the device started tracking time in the past
    if (deviceStartTime >= nowTime) throw Toastbox::RuntimeError("MSP::TimeState.start invalid");
    
    // Require at least `ElapsedHoursMin` of data before we institute an adjustment
    constexpr auto ElapsedDurationMin = std::chrono::hours(12);
    const std::chrono::hours elapsedHours = std::chrono::duration_cast<std::chrono::hours>(nowTime-deviceStartTime);
    if (elapsedHours < ElapsedDurationMin) return {};
    
    const Time::Clock::duration drift = nowTime-deviceNowTime;
    constexpr auto DriftDurationIgnore = Time::Clock::duration(2); // Ignored drift: <=2 ticks
    constexpr auto DriftDurationExcessive = std::chrono::hours(1); // Excessive drift: >=1 hour
    // Short-circuit if there's 0-2 ticks of drift, since that could just be noise
    if (std::chrono::abs(drift) <= DriftDurationIgnore) return {};
    // Check for excessive drift
    if (std::chrono::abs(drift) >= DriftDurationExcessive) {
        throw Toastbox::RuntimeError("excessive drift detected (%s)", Toastbox::DurationString(false, std::chrono::abs(drift)).c_str());
    }
    
    const Time::Clock::duration elapsed = nowTime-deviceStartTime;
    const double target = (double)drift.count() / elapsed.count();
    struct {
        Time::TicksU64 interval = 0;
        Time::TicksS64 delta = 0;
        double err = INFINITY;
    } best;
    
    static_assert(Time::TicksFreq::den == 1); // Check assumption
    for (int i=1; i<=Time::TicksFreq::num; i++) {
        const Time::TicksU64 interval = (elapsed.count() * i) / std::abs(drift.count());
        const Time::TicksS64 delta = (drift.count()>=0 ? i : -i);
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
    
    return {
        .value    = Toastbox::Cast<Value>(drift.count()),
        .interval = Toastbox::Cast<Interval>(best.interval),
        .delta    = Toastbox::Cast<Delta>(best.delta),
    };
}

} // namespace Time
