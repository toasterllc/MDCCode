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

namespace MDCStudio::BatteryLifeEstimate {

struct Constants {
    uint32_t batteryImageCaptureCapacity = 0;
    float batteryDailySelfDischarge = 0;
};

struct Parameters {
    std::chrono::seconds motionStimulusInterval = std::chrono::seconds(0);
    std::chrono::seconds buttonStimulusInterval = std::chrono::seconds(0);
};

constexpr Constants WorstCase = {
    .batteryImageCaptureCapacity = 50000,
    .batteryDailySelfDischarge = 0.0017083156,     // 5% per month == 1-(1-.05)^(1/30) per day
};

constexpr Constants BestCase = {
    .batteryImageCaptureCapacity = 80000,
    .batteryDailySelfDischarge = 0.0006731968785,  // 2% per month == 1-(1-.02)^(1/30) per day
};

struct Estimator {
    Estimator(const Constants& consts,
        const Parameters& params,
        const MSP::Triggers& triggers) : _consts(consts), _params(params), _triggers(triggers) {
        
        assert(params.motionStimulusInterval.count() > 0);
        assert(params.buttonStimulusInterval.count() > 0);
    }
    
    std::chrono::seconds estimate() {
        // Since _MSPState is static, require that we're called from a single thread (the main thread) only.
        // In the future we'd like to remove this requirement; see comment about _MSPState.
        assert([NSThread isMainThread]);
        
        _batteryLevel = 1;
        _MSPState.settings.triggers = _triggers;
        
        const auto timeStart = Time::Clock::now();
        _time = Time::Clock::TimeInstantFromTimePoint(timeStart);
        _Triggers::Init(_time);
        
        _batteryDailySelfDischargeSchedule();
        
        // Fast-forward through events
        for (;;) {
            _Triggers::Event* ev = _Triggers::EventFront();
            assert(ev);
            if (ev->time > _time) break;
            _Triggers::EventPop();
            _eventHandle(*ev);
        }
        
        printf("===== LIVE =====\n");
        _live = true;
        
        uint64_t i;
        for (i=0;; i++) {
            _Triggers::Event& ev = *_Triggers::EventFront();
            _Triggers::EventPop();
            
            // Make our current time the event's time
            _time = ev.time;
            
            // Print the current time + battery level
//            _printTime(); printf("Battery level: %.1f%%\n", _batteryLevel*100);
            
            // Handle the event
            _eventHandle(ev);
            
            // Bail once the battery level is below our threshold
            if (_batteryLevel < _BatteryEmptyLevel) break;
            
            _motionStimulusSchedule();
            _buttonStimulusSchedule();
        }
        
        printf("ITERATIONS: %ju\n", (uintmax_t)i);
        
        // Print the current time + battery level
//        _printTime(); printf("Battery level: %.1f%%\n", _batteryLevel*100);
        
        const auto timeEnd = Time::Clock::TimePointFromTimeInstant(_time);
        const std::chrono::seconds duration = std::chrono::duration_cast<std::chrono::seconds>(timeEnd-timeStart);
        const date::days durationDays = std::chrono::duration_cast<date::days>(timeEnd-timeStart);
        printf("Battery lasted %ju days (%ju seconds)\n", (uintmax_t)durationDays.count(), (uintmax_t)duration.count());
        
        if (duration < _BatteryLifeMin) return _BatteryLifeMin;
        if (duration > _BatteryLifeMax) return _BatteryLifeMax;
        return duration;
    }
    
    // TODO: for now MSP::State is static which is gross and means we're not thread safe.
    // In the future, figure out how to make it non-static, but still share the T_MSPTriggers
    // code with MSPApp.
    static inline MSP::State _MSPState;
    using _Triggers = T_MSPTriggers<_MSPState, bool>;
    
    _Triggers::Event _batteryDailySelfDischargeEvent = {};
    _Triggers::Event _motionStimulusEvent = {};
    _Triggers::Event _buttonStimulusEvent = {};
    
    void _eventInsert(_Triggers::Event& ev, const Time::Instant& time) {
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
            _batteryLevel *= 1-_consts.batteryDailySelfDischarge;
        }
        _batteryDailySelfDischargeSchedule();
    }
    
    void _batteryDailySelfDischargeSchedule() {
        _eventInsert(_batteryDailySelfDischargeEvent, _time+Time::Day);
    }
    
    bool _captureStart(_Triggers::CaptureImageEvent& ev, const Time::Instant& time) {
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
        assert(_live);
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
//            ((_time+60)/60)*60
//            
//            ((0+60)/60)*60 = 60
//            ((1+60)/60)*60 = 60
//            ((59+60)/60)*60 = 60
//            
//            ((60+60)/60)*60 = 120
//            ((60+60)/60)*60 = 120
            
            _eventInsert(_motionStimulusEvent, _NextInterval(_time, _params.motionStimulusInterval));
        }
    }
    
    void _buttonStimulus() {
        assert(_live);
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
            _eventInsert(_buttonStimulusEvent, _NextInterval(_time, _params.buttonStimulusInterval));
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
        const auto tp = tz.to_local(Time::Clock::to_sys(Time::Clock::TimePointFromTimeInstant(_time)));
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
        return 1.f / _consts.batteryImageCaptureCapacity;
    }
    
    static constexpr date::days _BatteryLifeMin = date::days(1);
    static constexpr date::days _BatteryLifeMax = date::days(365*3);
    
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

} // namespace MDCStudio::BatteryLifeEstimate
