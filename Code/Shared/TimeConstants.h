#pragma once
#include "Time.h"

namespace Time {

static constexpr Time::Ticks32 Day         = (Time::Ticks32)     24*60*60*Time::TicksFreq::num;
static constexpr Time::Ticks32 Year        = (Time::Ticks32) 365*24*60*60*Time::TicksFreq::num;

static_assert(TicksFreq::den == 1); // Check assumption that TicksFreq is an integer
static_assert(Day == 1382400); // Debug
static_assert(Year == 504576000); // Debug

} // namespace Time
