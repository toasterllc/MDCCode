#pragma once
#include "Time.h"

namespace Time {

static constexpr Time::TicksS32 Day  = (Time::TicksS32)     24*60*60*Time::TicksFreq::num;
static constexpr Time::TicksS32 Year = (Time::TicksS32) 365*24*60*60*Time::TicksFreq::num;

static_assert(TicksFreq::den == 1); // Check assumption that TicksFreq is an integer
static_assert(Day == 1382400); // Debug
static_assert(Year == 504576000); // Debug

} // namespace Time
