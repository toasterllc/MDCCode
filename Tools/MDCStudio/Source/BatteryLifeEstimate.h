#pragma once
#include <chrono>
#include <list>
#include "DeviceSettings.h"
#include "Code/Shared/Clock.h"
#include "Code/Shared/MSPTriggers.h"
#include "date/date.h"

namespace MDCStudio::BatteryLifeEstimate {

struct Constants {
    float batteryDailySelfDischarge = 0;
//    float batteryEmptyLevel                 = 0;
//    uint32_t batteryImageCaptureCapacity    = 0;
};

struct Parameters {
    std::chrono::seconds stimulusInterval = std::chrono::seconds(0); // Motion / button press interval
};

// BatteryEmptyLevel: consider battery dead at 2%
// This needs to match MSP's battery trap level
constexpr float BatteryEmptyLevel = 0.02;

// BatteryImageCaptureCapacity: assume the device's battery can capture 60000 images with a full battery
constexpr uint32_t BatteryImageCaptureCapacity = 60000;

constexpr Constants WorstCase = {
    .batteryDailySelfDischarge = 0.0017083156,     // 5% per month == 1-(1-.05)^(1/30) per day
//    .batteryEmptyLevel              = BatteryEmptyLevel,
//    .batteryImageCaptureCapacity    = BatteryImageCaptureCapacity,
};

constexpr Constants BestCase = {
    .batteryDailySelfDischarge = 0.0006731968785,  // 2% per month == 1-(1-.02)^(1/30) per day
//    .batteryEmptyLevel              = BatteryEmptyLevel,
//    .batteryImageCaptureCapacity    = BatteryImageCaptureCapacity,
};

static MSP::State _MSPState;
using _Triggers = T_MSPTriggers<_MSPState, bool>;

static void _EventInsert(_Triggers::Event& ev, const Time::Instant& time) {
    _Triggers::EventInsert(ev, time);
}

static bool _EventInsert(_Triggers::Event& ev, MSP::Repeat& repeat) {
    const Time::Ticks32 delta = _Triggers::RepeatAdvance(repeat);
    // delta=0 means Repeat=never, in which case we don't reschedule the event
    if (delta) {
        _Triggers::EventInsert(ev, ev.time+delta);
        return true;
    }
    return false;
}

static void _EventHandle(_Triggers::Event& ev) {
    using T = _Triggers::Event::Type;
    switch (ev.type) {
    case T::TimeTrigger:
        break;
    case T::MotionEnablePower:
        break;
    case T::MotionEnable:
        break;
    case T::MotionDisable:
        break;
    case T::MotionUnsuppressPower:
        break;
    case T::MotionUnsuppress:
        break;
    case T::CaptureImage:
        break;
    default:
        abort();
    }
}

inline std::chrono::seconds Estimate(const Constants& consts,
    const Parameters& params, const MSP::Triggers& mspTriggers) {
    
    _MSPState.settings.triggers = mspTriggers;
    
    const Time::Instant now = Time::Clock::TimeInstantFromTimePoint(Time::Clock::now());
    _Triggers::Init(now);
    
    // Fast-forward through events
    for (;;) {
        _Triggers::Event& ev = *_Triggers::EventFront();
        _Triggers::EventPop();
        _EventHandle(ev);
    }
        
        
//        if (!ev || (ev->time > startTime)) break;
//        _EventHandle(_EventPop());
    
    
//    constexpr float ImageCaptureCost = 1.f / BatteryImageCaptureCapacity;
//    
//    struct Trigger {
//        virtual ~Trigger() {}
//    };
//    using TriggerPtr = std::unique_ptr<Trigger>;
//    
//    struct Event {
//        Time::Clock::time_point time;
//        virtual ~Event() {}
//    };
//    using EventPtr = std::unique_ptr<Event>;
//    
//    struct BatteryDailySelfDischargeEvent : Event {};
//    struct StimulusEvent : Event {};
//    
//    float batteryLevel = 1;
//    
//    std::list<TriggerPtr> triggers;
//    std::list<EventPtr> events;
//    for (size_t i=0; i<triggers.count; i++) {
//        const auto& trigger = triggers.triggers[i];
//        
//    }
//    
//    
//    for (;;) {
//        EventPtr event = std::move(events.front());
//        events.pop_front();
//        
//        if (auto x = dynamic_cast<BatteryDailySelfDischargeEvent*>(event.get())) {
//            batteryLevel *= 1-consts.batteryDailySelfDischarge;
//            
//        
//        } else if (auto x = dynamic_cast<StimulusEvent*>(event.get())) {
//            for (auto& trigger : triggers) {
//                
//            }
//        
//        } else {
//            // Unknown type
//            abort();
//        }
//        
//        printf("Battery level: %.1f%%\n", batteryLevel*100);
//    }
    
    return std::chrono::seconds(0);
}

} // namespace MDCStudio::BatteryLifeEstimate
