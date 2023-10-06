#pragma once
#include <sstream>
#include <string>
#include "Time.h"
#include "Code/Lib/Toastbox/DurationString.h"

namespace Time {

static std::string StringForTimeInstant(Time::Instant t, bool relative=false) {
    using namespace std::chrono;
    std::stringstream ss;
    if (Time::Absolute(t)) {
        const date::time_zone& tz = *date::current_zone();
        const auto tpDevice = Time::Clock::TimePointFromTimeInstant(t);
        const auto tpLocal = tz.to_local(date::clock_cast<std::chrono::system_clock>(tpDevice));
        ss << tpLocal;
        if (relative) {
            const auto tpNow = Time::Clock::now();
            ss << " (" << Toastbox::DurationString(true, duration_cast<seconds>(tpNow-tpDevice)) << " ago)";
        } else {
            ss << " (0x" << std::setfill('0') << std::setw(16) << std::hex << t << ")";
        }
    } else {
        ss << "0x" << std::setfill('0') << std::setw(16) << std::hex << t << " [relative]";
    }
    return ss.str();
}

static std::string StringForTimeState(const MSP::TimeState& state) {
    std::stringstream ss;
    const Time::Instant deviceStart = state.start;
    const Time::Instant deviceInstant = state.time;
    const Time::Clock::time_point nowTime = Time::Clock::now();
    const Time::Instant nowInstant = Time::Clock::TimeInstantFromTimePoint(nowTime);
    
    ss       << "  MDC Start: " << StringForTimeInstant(deviceStart) << "\n";
    ss       << "   MDC Time: " << StringForTimeInstant(deviceInstant) << "\n";
    ss       << "        Now: " << StringForTimeInstant(nowInstant) << "\n";
    
    if (Time::Absolute(deviceInstant)) {
        const Time::Clock::time_point deviceTime = Time::Clock::TimePointFromTimeInstant(deviceInstant);
        const std::chrono::microseconds delta = deviceTime-nowTime;
        ss   << "      Delta: " << std::showpos << (intmax_t)delta.count() << " us \n";
    }
    return ss.str();
}


static std::string StringForTimeAdjustment(const MSP::TimeAdjustment& adj) {
    std::stringstream ss;
    ss << "   value: " << std::to_string(adj.value) << "\n";
    ss << " counter: " << std::to_string(adj.counter) << "\n";
    ss << "interval: " << std::to_string(adj.interval) << "\n";
    ss << "   delta: " << std::to_string(adj.delta) << "\n";
    return ss.str();
}

} // namespace Time
