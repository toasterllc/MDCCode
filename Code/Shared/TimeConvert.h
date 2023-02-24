#pragma once
#include <chrono>
#include "date/date.h"
#include "date/tz.h"

namespace Time {

// Current(): returns the current time instant
//
// Note that we can't use Unix time here (ie time()) because Unix time is a non-linear
// representation of time. That is, when a leap second occurs, Unix time doesn't
// increment for that particular second, so performing duration calculations across
// leap seconds produces results that would disagree with a stopwatch running over
// the same period (by a magnitude of the number of leap seconds that occurred).
//
// Instead we use the C++ utc_clock which properly handles our duration math.

inline Instant Current() {
    using namespace std::chrono;
    using namespace date;
    
    const time_point<utc_clock> epoch = clock_cast<utc_clock>(system_clock::from_time_t(AbsoluteEpochUnix));
    const time_point<utc_clock> now = utc_clock::now();
    const microseconds delta = duration_cast<microseconds>(now-epoch);
    return AbsoluteBit | (Instant)delta.count();
}

} // namespace Time
