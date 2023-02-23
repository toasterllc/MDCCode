#pragma once

namespace Time {

// Instant: represents a particular moment in time
// Encoded as the linear number of milliseconds since our epoch (defined by EpochUnix)
using Instant = uint64_t;

static constexpr uint64_t EpochUnix = 1640995200; // 2022-01-01 00:00:00 +0000

static constexpr bool Absolute(const Instant& t) {
    return t&((uint64_t)1<<63);
}

//static constexpr Time TimeAbsoluteUnixReference = 1640995200; // 2022-01-01 00:00:00 +0000
//static constexpr Time TimeAbsoluteBase = (Time)1<<63;
//
//static constexpr uint64_t UnixTimeFromTime(Time t) {
//    return (t&(~TimeAbsoluteBase)) + TimeAbsoluteUnixReference;
//}
//
//static constexpr uint64_t TimeFromUnixTime(uint64_t t) {
//    return TimeAbsoluteBase | (t-TimeAbsoluteUnixReference);
//}

} // namespace Time
