#pragma once
#include "Time.h"

namespace Time {

static constexpr Time::TicksS32 Second = (Time::TicksS32) Time::TicksFreq::num;
static constexpr Time::TicksS32 Minute = (Time::TicksS32)            60*Second;
static constexpr Time::TicksS32 Hour   = (Time::TicksS32)            60*Minute;
static constexpr Time::TicksS32 Day    = (Time::TicksS32)              24*Hour;
static constexpr Time::TicksS32 Year   = (Time::TicksS32)              365*Day;

static_assert(TicksFreq::den == 1); // Check assumption that TicksFreq is an integer
static_assert(Second == 16); // Debug
static_assert(Minute == 960); // Debug
static_assert(Hour == 57600); // Debug
static_assert(Day == 1382400); // Debug
static_assert(Year == 504576000); // Debug

} // namespace Time
