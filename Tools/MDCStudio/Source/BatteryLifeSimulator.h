#pragma once
#include <chrono>
#include <list>
#include <iostream>
#include "DeviceSettings.h"
#include "Code/Shared/Clock.h"
#include "Code/Shared/Time.h"
#include "Code/Shared/TimeConstants.h"
#include "Code/Shared/MSPTriggers.h"
#include "date/date.h"

namespace MDCStudio::BatteryLifeSimulator {

struct Constants {
    static constexpr std::chrono::seconds BatteryLifeMin = date::days(1);
    static constexpr std::chrono::seconds BatteryLifeMax = date::years(3);
    std::chrono::seconds motionStimulusInterval = std::chrono::minutes(10);
    std::chrono::seconds buttonStimulusInterval = std::chrono::hours(6);
};

struct Parameters {
    uint32_t batteryImageCaptureCapacity = 0;
    float batteryDailySelfDischarge = 0;
};

constexpr Parameters WorstCase = {
    .batteryImageCaptureCapacity = 50000,
    .batteryDailySelfDischarge = 0.0017083156,     // 5% per month == 1-(1-.05)^(1/30) per day
};

constexpr Parameters BestCase = {
    .batteryImageCaptureCapacity = 80000,
    .batteryDailySelfDischarge = 0.0006731968785,  // 2% per month == 1-(1-.02)^(1/30) per day
};

struct Point {
    std::chrono::seconds time = std::chrono::seconds(0);
    float batteryLevel = 0;
};

struct Simulator {
    Simulator(const Constants& consts,
        const Parameters& params,
        const MSP::Triggers& triggers) : _consts(consts), _params(params), _triggers(triggers) {
        
        assert(consts.motionStimulusInterval.count() > 0);
        assert(consts.buttonStimulusInterval.count() > 0);
    }
    
    // _BatteryLevelNormalize(): adjust the battery level `x` so that it spans [0,1].
    // This is so that 1 maps to 1 and _BatteryEmptyLevel maps to 0.
    static float _BatteryLevelNormalize(float x) {
        return (x-_BatteryEmptyLevel) / (1-_BatteryEmptyLevel);
    }
    
    std::vector<Point> simulate() {
        // Since _MSPState is static, require that we're called from a single thread (the main thread) only.
        // In the future we'd like to remove this requirement; see comment about _MSPState.
        assert([NSThread isMainThread]);
        auto debugTimeStart = std::chrono::steady_clock::now();
        
        _batteryLevel = 1;
        _MSPState.settings.triggers = _triggers;
        
        const Time::Instant timeStart = Time::Clock::TimeInstantFromTimePoint(Time::Clock::now());
        
        _time = timeStart;
        _Triggers::Init(_time);
        
        // Insert the initial point where the battery is fully charged
        std::vector<Point> points = {{
            .time = _duration(timeStart),
            .batteryLevel = _BatteryLevelNormalize(_batteryLevel),
        }};
        
        uint64_t i;
        for (i=0;; i++) {
            _batteryDailySelfDischargeSchedule();
            _motionStimulusSchedule();
            _buttonStimulusSchedule();
            
            _Triggers::Event& ev = *_Triggers::EventFront();
            _Triggers::EventPop();
            
            // Make our current time the event's time
            _time = ev.time;
            
            // Go live when we hit the current time
            if (!_live) {
                if (_time >= timeStart) {
                    _live = true;
                }
            }
            
            // Print the current time + battery level
//            _printTime(); printf("Battery level: %.1f%%\n", _batteryLevel*100);
            
            // Handle the event
            _eventHandle(ev);
            
            const std::chrono::seconds duration = _duration(timeStart);
            if (duration != points.back().time) {
                points.push_back({
                    .time = duration,
                    .batteryLevel = std::max(0.f, _BatteryLevelNormalize(_batteryLevel)),
                });
            }
            
            // Bail once the battery level is below our threshold
            if (_batteryLevel < _BatteryEmptyLevel) break;
        }
        
        // Bail once the battery level is below our threshold
        auto debugTimeEnd = std::chrono::steady_clock::now();
        auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(debugTimeEnd-debugTimeStart);
        printf("%ju ITERATIONS TOOK %ju ms (%ju points)\n", (uintmax_t)i, (uintmax_t)durationMs.count(), (uintmax_t)points.size());
        
        // Extend battery life to Constants::BatteryLifeMin
        if (points.back().time < Constants::BatteryLifeMin) {
            points.push_back({
                .time = Constants::BatteryLifeMin,
                .batteryLevel = points.back().batteryLevel,
            });
        }
        
        // Trim battery life to Constants::BatteryLifeMax
        if (points.back().time > Constants::BatteryLifeMax) {
            while (points.back().time > Constants::BatteryLifeMax) {
                points.pop_back();
            }
            points.push_back({
                .time = Constants::BatteryLifeMax,
                .batteryLevel = points.back().batteryLevel,
            });
        }
        
        return points;
        
        // Print the current time + battery level
//        _printTime(); printf("Battery level: %.1f%%\n", _batteryLevel*100);
        
//        const auto timeEnd = Time::Clock::TimePointFromTimeInstant(_time);
//        const std::chrono::seconds duration = std::chrono::duration_cast<std::chrono::seconds>(timeEnd-timeStart);
//        const date::days durationDays = std::chrono::duration_cast<date::days>(timeEnd-timeStart);
//        printf("Battery lasted %ju days (%ju seconds)\n", (uintmax_t)durationDays.count(), (uintmax_t)duration.count());
//        
//        return points;
    }
    
    // TODO: for now MSP::State is static which is gross and means we're not thread safe.
    // In the future, figure out how to make it non-static, but still share the T_MSPTriggers
    // code with MSPApp.
    static inline MSP::State _MSPState;
    using _Triggers = T_MSPTriggers<_MSPState, bool>;
    
    _Triggers::Event _batteryDailySelfDischargeEvent = {};
    _Triggers::Event _motionStimulusEvent = {};
    _Triggers::Event _buttonStimulusEvent = {};
    
    std::chrono::seconds _duration(Time::Instant timeStart) {
        const auto t1 = Time::Clock::TimePointFromTimeInstant(timeStart);
        const auto t2 = Time::Clock::TimePointFromTimeInstant(_time);
        return std::chrono::duration_cast<std::chrono::seconds>(t2-t1);
    }
    
    void _eventInsert(_Triggers::Event& ev, Time::Instant time) {
        _Triggers::EventInsert(ev, time);
    }
    
    void _eventInsert(_Triggers::Event& ev, MSP::Repeat& repeat) {
        const Time::Ticks32 delta = _Triggers::RepeatAdvance(repeat);
        // delta=0 means Repeat=never, in which case we don't reschedule the event
        if (delta) _Triggers::EventInsert(ev, ev.time+delta);
    }
    
    void _batteryDailySelfDischarge() {
        if (_live) {
//            _printTime(); printf("Battery self-discharge\n");
            _batteryLevel *= 1-_params.batteryDailySelfDischarge;
        }
        _batteryDailySelfDischargeSchedule();
    }
    
    void _batteryDailySelfDischargeSchedule() {
        if (_batteryDailySelfDischargeScheduleNeeded()) {
            _eventInsert(_batteryDailySelfDischargeEvent, _NextInterval(_time, date::days(1)));
        }
    }
    
    bool _batteryDailySelfDischargeScheduleNeeded() const {
        // If the motion stimulus is already scheduled: don't reschedule
        if (_batteryDailySelfDischargeEvent.scheduled()) return false;
        return true;
    }
    
    bool _captureStart(_Triggers::CaptureImageEvent& ev, Time::Instant time) {
        // Bail if the CaptureImageEvent is already underway
        if (ev.countRem) return false;
        
        // Reset capture count
        ev.countRem = ev.capture->count;
        if (ev.countRem) {
            _eventInsert(ev, time);
        }
        return true;
    }
    
    void _motionStimulus() {
        if (!_live) return;
//        _printTime(); printf("Motion stimulus\n");
        
        // When motion occurs, start captures for each enabled motion trigger
        for (auto it=_Triggers::MotionTriggerBegin(); it!=_Triggers::MotionTriggerEnd(); it++) {
//            _printTime(); printf("Motion trigger\n");
            
            _Triggers::MotionTrigger& trigger = *it;
            
            // Check if we should ignore this trigger
            if (!trigger.enabled()) continue;
            
            // Start capture
            const bool captureStarted = _captureStart(trigger, _time);
            // _captureStart() returns false if a capture is already in progress for this trigger.
            // Short-circuit if that's the case.
            if (!captureStarted) continue;
            
            // Update the number of motion triggers remaining.
            // If this was the last trigger that we're allowed, set the `StateMaxImageCount` bit,
            // which will .
            if (trigger.countRem) {
                trigger.countRem--;
                if (!trigger.countRem) {
                    trigger.hitMaxImageCount();
                }
            }
            
            // Suppress motion for the specified duration, if suppression is enabled
            const Time::Ticks32 suppressTicks = trigger.base().suppressTicks;
            if (suppressTicks) {
                // Suppress power/motion immediately
                trigger.suppress();
                
                // Schedule MotionUnsuppressEvent
                const Time::Instant unsuppressTime = _time+suppressTicks;
                _eventInsert(static_cast<_Triggers::MotionUnsuppressEvent&>(trigger), unsuppressTime);
            }
        }
    }
    
    bool _motionStimulusScheduleNeeded() const {
        // If the motion stimulus is already scheduled: don't reschedule
        if (_motionStimulusEvent.scheduled()) return false;
        // Check if there are any motion triggers that are enabled (.enabled()==true) for which
        // captures aren't currently underway (ev.countRem==0)
        for (auto it=_Triggers::MotionTriggerBegin(); it!=_Triggers::MotionTriggerEnd(); it++) {
            const _Triggers::MotionTrigger& trigger = *it;
            const _Triggers::CaptureImageEvent& ev = trigger;
            if (trigger.enabled() && !ev.countRem) return true;
        }
        return false;
    }
    
    // _NextInterval(): returns the next Time::Instant that occurs at a regular interval of `interval`.
    // This is necessary so that our stimuluses occur at regular X-second intervals irrespective of
    // events that are occuring, as opposed to the stimulus occuring at LastEventTime+interval,
    // which would give an optimisic view of the battery life.
    static Time::Instant _NextInterval(Time::Instant t, std::chrono::seconds interval) {
        const Time::Ticks64 ticks = Time::Clock::TicksFromDuration(interval);
        return ((t+ticks)/ticks)*ticks;
    }
    
    void _motionStimulusSchedule() {
        if (_motionStimulusScheduleNeeded()) {
            _eventInsert(_motionStimulusEvent, _NextInterval(_time, _consts.motionStimulusInterval));
        }
    }
    
    void _buttonStimulus() {
        if (!_live) return;
//        _printTime(); printf("Button stimulus\n");
        for (auto it=_Triggers::ButtonTriggerBegin(); it!=_Triggers::ButtonTriggerEnd(); it++) {
//            _printTime(); printf("Button trigger\n");
            _captureStart(*it, _time);
        }
    }
    
    bool _buttonStimulusScheduleNeeded() const {
        // If the button stimulus is already scheduled: don't reschedule
        if (_buttonStimulusEvent.scheduled()) return false;
        // Check if there are any button triggers that for which
        // captures aren't currently underway (ev.countRem==0)
        for (auto it=_Triggers::ButtonTriggerBegin(); it!=_Triggers::ButtonTriggerEnd(); it++) {
            const _Triggers::ButtonTrigger& trigger = *it;
            const _Triggers::CaptureImageEvent& ev = trigger;
            if (!ev.countRem) return true;
        }
        return false;
    }
    
    void _buttonStimulusSchedule() {
        if (_buttonStimulusScheduleNeeded()) {
            _eventInsert(_buttonStimulusEvent, _NextInterval(_time, _consts.buttonStimulusInterval));
        }
    }
    
    void _timeTrigger(_Triggers::TimeTriggerEvent& ev) {
        _Triggers::TimeTrigger& trigger = ev.trigger();
        if (_live) {
            _captureStart(trigger, ev.time);
        }
        _eventInsert(ev, ev.repeat);
    }
    
    void _motionEnable(_Triggers::MotionEnableEvent& ev) {
        _Triggers::MotionTrigger& trigger = ev.trigger();
        trigger.enable();
        
        // Schedule the MotionDisableEvent, if applicable.
        // This needs to happen before we reschedule `ev` because we need its .time to
        // properly schedule the MotionDisableEvent!
        const uint32_t durationTicks = trigger.base().durationTicks;
        if (durationTicks) {
            _eventInsert(static_cast<_Triggers::MotionDisableEvent&>(trigger), ev.time+durationTicks);
        }
        
        // Reschedule MotionEnableEvent for its next trigger time
        _eventInsert(ev, ev.repeat);
    }
    
    void _motionDisable(_Triggers::MotionDisableEvent& ev) {
        _Triggers::MotionTrigger& trigger = (_Triggers::MotionTrigger&)ev;
        trigger.disable();
    }
    
    void _motionUnsuppress(_Triggers::MotionUnsuppressEvent& ev) {
        assert(_live);
        _Triggers::MotionTrigger& trigger = (_Triggers::MotionTrigger&)ev;
        trigger.unsuppress();
    }
    
    void _captureImage(_Triggers::CaptureImageEvent& ev) {
        // We should never get a CaptureImageEvent event while in fast-forward mode
        assert(_live);
        
        _batteryLevel -= _imageCaptureCost();
        
        ev.countRem--;
        if (ev.countRem) {
            _eventInsert(ev, ev.time+ev.capture->delayTicks);
        }
    }
    
    void _eventHandle(_Triggers::Event& ev) {
        // Handle our special events
        if (&ev == &_batteryDailySelfDischargeEvent) {
            return _batteryDailySelfDischarge();
        } else if (&ev == &_motionStimulusEvent) {
            return _motionStimulus();
        } else if (&ev == &_buttonStimulusEvent) {
            return _buttonStimulus();
        }
        
        // Handle the event
        using T = _Triggers::Event::Type;
        switch (ev.type) {
        case T::TimeTrigger:
            return _timeTrigger(static_cast<_Triggers::TimeTriggerEvent&>(ev));
        case T::MotionEnablePower:
            // Should never occur
            abort();
        case T::MotionEnable:
            return _motionEnable(static_cast<_Triggers::MotionEnableEvent&>(ev));
        case T::MotionDisable:
            return _motionDisable(static_cast<_Triggers::MotionDisableEvent&>(ev));
        case T::MotionUnsuppressPower:
            // Should never occur
            abort();
        case T::MotionUnsuppress:
            return _motionUnsuppress(static_cast<_Triggers::MotionUnsuppressEvent&>(ev));
        case T::CaptureImage:
            return _captureImage(static_cast<_Triggers::CaptureImageEvent&>(ev)); break;
        }
    }
    
    void _printTime() {
        const date::time_zone& tz = *date::current_zone();
        const auto tp = tz.to_local(date::clock_cast<std::chrono::system_clock>(
            Time::Clock::TimePointFromTimeInstant(_time)));
        const auto days = date::floor<date::days>(tp);
        const auto ymd = date::year_month_day(days);
        const auto hhmmss = date::make_time(tp-days);
        
        std::cout << "[ ";
        std::cout << ymd.year() << "-" << ymd.month() << "-" << ymd.day();
        std::cout << " @ ";
        std::cout << hhmmss.hours().count() << ":" << hhmmss.minutes().count() << ":" << hhmmss.seconds().count();
        std::cout << " ] ";
    }
    
    float _imageCaptureCost() const {
        return 1.f / _params.batteryImageCaptureCapacity;
    }
    
//    static constexpr date::days _BatteryLifeDurationMin = date::days(1);
//    static constexpr date::days _BatteryLifeDurationMax = date::days(365*3);
    
    // BatteryEmptyLevel: consider battery dead at 2%
    // This needs to match MSP's battery trap level
    static constexpr float _BatteryEmptyLevel = 0.02;
    
    const Constants _consts;
    const Parameters _params;
    const MSP::Triggers _triggers;
    
    Time::Instant _time = 0;
    bool _live = false;
    float _batteryLevel = 0;
};

} // namespace MDCStudio::BatteryLifeSimulator
