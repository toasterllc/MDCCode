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
    float batteryDailySelfDischarge = 0;
};

struct Parameters {
    std::chrono::seconds stimulusInterval = std::chrono::seconds(0); // Motion / button press interval
};

constexpr Constants WorstCase = {
    .batteryDailySelfDischarge = 0.0017083156,     // 5% per month == 1-(1-.05)^(1/30) per day
};

constexpr Constants BestCase = {
    .batteryDailySelfDischarge = 0.0006731968785,  // 2% per month == 1-(1-.02)^(1/30) per day
};

struct Estimator {
    Estimator(const Constants& consts,
        const Parameters& params,
        const MSP::Triggers& triggers) : _consts(consts), _params(params), _triggers(triggers) {
        
        assert(params.stimulusInterval.count() > 0);
    }
    
    std::chrono::seconds estimate() {
        _batteryLevel = 1;
        _MSPState.settings.triggers = _triggers;
        
        _time = Time::Clock::TimeInstantFromTimePoint(Time::Clock::now());
        _Triggers::Init(_time);
        
        // Insert our special events (_BatteryDailySelfDischargeEvent / _ExternalStimulusEvent)
        // by calling their respective event functions
        _batteryDailySelfDischarge();
        _externalStimulus();
        
        // Fast-forward through events
        for (;;) {
            _Triggers::Event* ev = _Triggers::EventFront();
            assert(ev);
            if (ev->time > _time) break;
            _Triggers::EventPop();
            _eventHandle(*ev);
        }
        
        _live = true;
        
        for (;;) {
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
        }
        
        return std::chrono::seconds(0);
    }
    
    static inline MSP::State _MSPState;
    using _Triggers = T_MSPTriggers<_MSPState, bool>;
    
    static inline _Triggers::Event _BatteryDailySelfDischargeEvent = {};
    static inline _Triggers::Event _ExternalStimulusEvent = {};
    
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
            _printTime(); printf("Battery self-discharge\n");
            _batteryLevel *= 1-_consts.batteryDailySelfDischarge;
        }
        _eventInsert(_BatteryDailySelfDischargeEvent, _time+Time::Day);
    }
    
    void _handleMotion() {
        // When motion occurs, start captures for each enabled motion trigger
        for (auto it=_Triggers::MotionTriggerBegin(); it!=_Triggers::MotionTriggerEnd(); it++) {
//            _printTime(); printf("Motion trigger\n");
            
            _Triggers::MotionTrigger& trigger = *it;
            
            // Check if we should ignore this trigger
            if (!trigger.enabled()) continue;
            
            // Capture images for the trigger
            _captureImages(trigger);
            
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
    
    void _handleButton() {
        for (auto it=_Triggers::ButtonTriggerBegin(); it!=_Triggers::ButtonTriggerEnd(); it++) {
            _printTime(); printf("Button trigger\n");
            _captureImages(*it);
        }
    }
    
    void _externalStimulus() {
        if (_live) {
            _handleMotion();
            _handleButton();
        }
        _eventInsert(_ExternalStimulusEvent, _time + Time::Clock::TicksFromDuration(_params.stimulusInterval));
    }
    
    void _timeTrigger(_Triggers::TimeTriggerEvent& ev) {
        if (_live) {
            _printTime(); printf("Time trigger\n");
            _captureImages(ev.trigger());
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
    
    void _captureImages(_Triggers::CaptureImageEvent& ev) {
        assert(_live);
        _printTime(); printf("Capture %ju images\n", (uintmax_t)ev.capture->count);
        _batteryLevel -= ev.capture->count * _ImageCaptureCost;
    }
    
    void _eventHandle(_Triggers::Event& ev) {
        // Handle our special events
        if (&ev == &_BatteryDailySelfDischargeEvent) {
            return _batteryDailySelfDischarge();
        
        } else if (&ev == &_ExternalStimulusEvent) {
            return _externalStimulus();
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
            // Should never occur
            abort();
        }
    }
    
    void _printTime() {
        const auto tp = Time::Clock::to_sys(Time::Clock::TimePointFromTimeInstant(_time));
        const date::sys_days dp = date::floor<date::days>(tp);
        const date::year_month_day ymd = date::year_month_day(dp);
        const date::time_of_day<std::chrono::microseconds> hhmmss = date::make_time(tp - dp);
        
        std::cout << "[ ";
        std::cout << ymd.year() << "-" << ymd.month() << "-" << ymd.day();
        std::cout << " @ ";
        std::cout << hhmmss.hours().count() << ":" << hhmmss.minutes().count() << ":" << hhmmss.seconds().count();
        std::cout << " ] ";
    }
    
    // BatteryEmptyLevel: consider battery dead at 2%
    // This needs to match MSP's battery trap level
    static constexpr float _BatteryEmptyLevel = 0.02;

    // BatteryImageCaptureCapacity: assume the device's battery can capture 60000 images with a full battery
    static constexpr uint32_t _BatteryImageCaptureCapacity = 60000;
    
    // _ImageCaptureCost: the battery cost of a single image capture
    static constexpr float _ImageCaptureCost = 1.f / _BatteryImageCaptureCapacity;
    
    const Constants _consts;
    const Parameters _params;
    const MSP::Triggers _triggers;
    
    Time::Instant _time = 0;
    bool _live = false;
    float _batteryLevel = 0;
};

} // namespace MDCStudio::BatteryLifeEstimate
