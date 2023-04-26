#pragma once

namespace Time {

// TicksFreqHz: the number of ticks that occur per second
static constexpr uint16_t TicksFreqHz = 16;

// Ticks: a duration in ticks
// Using a signed value here so we can represent negative durations.
// (Clock.h needs negative durations for computing the difference between two timepoints,
// so we define `Ticks` as signed so Clock.h can use this type.)
using Ticks = int64_t;

// Instant: represents a particular moment in time
// Encoded as the linear count of ticks since our epoch,
// where our epoch is defined by `Epoch` in Clock.h
using Instant = uint64_t;

static constexpr Instant AbsoluteBit = (Instant)1<<63;

// Absolute(): returns whether the time instant is an absolute time (versus a relative time)
// The difference between the two is that an absolute time is a time delta since the epoch
// (AbsoluteEpochUnix), whereas a relative time is a time delta since the device booting. A
// relative time therefore can't be converted to an absolute time without knowing the
// absolute time that the device booted.
static constexpr bool Absolute(const Instant& t) {
    return t&AbsoluteBit;
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
