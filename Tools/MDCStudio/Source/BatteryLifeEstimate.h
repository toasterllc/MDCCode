#pragma once
#include <chrono>
#include <list>
#include "DeviceSettings.h"
#include "Code/Shared/Clock.h"
#include "date/date.h"
#include "/Users/dave/repos/MDCCode/Code/MSP430/MSPApp/Triggers.h"

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



//template<typename T_Dst, typename T_Src>
//T_Dst MyCast(std::unique_ptr<T_Src> src) {
//    if (auto x = dynamic_cast<typename T_Dst::element_type>(src.get())) {
//        return x;
//    }
//    abort();
//}

struct Estimator {
    struct _Trigger {
        const DeviceSettings::Trigger* base = nullptr;
        virtual ~_Trigger() {}
    };
    using _TriggerPtr = std::unique_ptr<_Trigger>;
    
    struct _TimeTrigger : _Trigger {};
    struct _MotionTrigger : _Trigger {
        bool enabled = false;
        
    };
    struct _ButtonTrigger : _Trigger {};
    
    struct _Event {
//        Event(date::utc_clock::time_point time) : time(time) {}
        date::local_seconds time;
//        virtual std::chrono::seconds advance(const Parameters& params) = 0;
        virtual ~_Event() {}
    };
    using _EventPtr = std::unique_ptr<_Event>;
    
    struct _BatteryDailySelfDischargeEvent : _Event {};
    struct _StimulusEvent : _Event {};
    
    struct _TriggerEvent : _Event {
        _Trigger* trigger = nullptr;
    };
    
    struct _TimeTriggerEvent : _TriggerEvent {};
    
    struct _MotionTriggerEvent : _TriggerEvent {};
    struct _MotionEnableEvent : _TriggerEvent {};
    struct _MotionDisableEvent : _TriggerEvent {};
    struct _MotionUnsuppressEvent : _TriggerEvent {};
    
    struct _ButtonEvent : _TriggerEvent {};
    
    Estimator(const Constants& consts,
        const Parameters& params,
        const DeviceSettings::Triggers& triggers) : _consts(consts), _params(params), _triggers(triggers) {
        
        
    }
    
    static void _Insert(std::list<_EventPtr>& events, _EventPtr&& event) {
        auto it = events.begin();
        // Find the spot to insert the event
        while (it!=events.end() && (*it)->time<event->time) it++;
        events.insert(it, std::move(event));
    }
    
//    inline auto _FutureTime(const T& now, Calendar::TimeOfDay timeOfDay) {
//        const auto midnight = floor<date::days>(now);
//        const auto t = midnight+timeOfDay;
//        if (t < now) return t;
//        return t-date::days(1);
//    }
    
//    static void _Advance(BatteryDailySelfDischargeEvent& x) {
//        x.time += date::days(1);
//    }
//    
//    static void _Advance(BatteryDailySelfDischargeEvent& x) {
//        x.time += date::days(1);
//    }
    
    void _advance(_BatteryDailySelfDischargeEvent& x) {
        x.time += date::days(1);
    }
    
    void _advance(_StimulusEvent& x) {
        x.time += _params.stimulusInterval;
    }
    
//    static std::vector<MSP::Triggers::Event> _EventsCreate(MSP::Triggers::Event::Type type,
//        Calendar::TimeOfDay timeOfDay, const Repeat* repeat, uint8_t idx) {
//        
//        using namespace std::chrono;
//        const date::time_zone& tz = *date::current_zone();
//        const auto now = tz.to_local(system_clock::now());
//        const auto pastTimeOfDay = _PastTime(now, timeOfDay);
//        
//        // Handle non-repeating events
//        if (!repeat) {
//            return { MSP::Triggers::Event{
//                .time = _TimeInstantForLocalTime(tz, pastTimeOfDay),
//                .type = type,
//                .repeat = { .type = MSP::Repeat::Type::Never, },
//                .idx = idx,
//            }};
//        }
//        
//        switch (repeat->type) {
//        case Repeat::Type::Daily:
//            return { MSP::Triggers::Event{
//                .time = _TimeInstantForLocalTime(tz, pastTimeOfDay),
//                .type = type,
//                .repeat = {
//                    .type = MSP::Repeat::Type::Daily,
//                    .Daily = { 1 },
//                },
//                .idx = idx,
//            }};
//        
//        case Repeat::Type::DaysOfWeek: {
//            const date::local_seconds tp = _PastDayOfWeek(now, timeOfDay, repeat->DaysOfWeek);
//            // Create the DaysOfWeek bitfield that's aligned to whatever day of
//            // the week `tp` is.
//            // This is necessary because the time that we return and the days
//            // bitfield need to be aligned so that they represent the same day.
//            const uint8_t days = _DaysOfWeekBitfield(tp, repeat->DaysOfWeek);
//            
//            return { MSP::Triggers::Event{
//                .time = _TimeInstantForLocalTime(tz, tp),
//                .type = type,
//                .repeat = {
//                    .type = MSP::Repeat::Type::Weekly,
//                    .Weekly = { days },
//                },
//                .idx = idx,
//            }};
//        }
//        
//        case Repeat::Type::DaysOfYear: {
//            const auto daysOfYear = Calendar::VectorFromDaysOfYear(repeat->DaysOfYear);
//            std::vector<MSP::Triggers::Event> events;
//            for (Calendar::DayOfYear doy : daysOfYear) {
//                // Determine if doy's month+day of the current year is in the past.
//                // If it's in the future, subtract one year and use that.
//                const date::local_seconds tp = _PastDayOfYear(now, timeOfDay, doy);
//                events.push_back({
//                    .time = _TimeInstantForLocalTime(tz, tp),
//                    .type = type,
//                    .repeat = {
//                        .type = MSP::Repeat::Type::Yearly,
//                        .Yearly = { _LeapYearPhase(tz, tp) },
//                    },
//                    .idx = idx,
//                });
//            }
//            return events;
//        }
//        
//        case Repeat::Type::DayInterval:
//            return { MSP::Triggers::Event{
//                .time = _TimeInstantForLocalTime(tz, pastTimeOfDay),
//                .type = type,
//                .repeat = {
//                    .type = MSP::Repeat::Type::Daily,
//                    .Daily = { Toastbox::Cast<decltype(MSP::Repeat::Daily.interval)>(repeat->DayInterval.count()) },
//                },
//                .idx = idx,
//            }};
//        
//        default:
//            abort();
//        }
//    }
    
    std::chrono::seconds estimate() {
        constexpr float ImageCaptureCost = 1.f / BatteryImageCaptureCapacity;
        
        using namespace std::chrono;
        using namespace DeviceSettings;
        const date::time_zone& tz = *date::current_zone();
        const date::local_seconds now = floor<std::chrono::seconds>(tz.to_local(system_clock::now()));
        const date::local_seconds start = now;
        date::local_seconds time = start;
        float batteryLevel = 1;
        
        std::list<_TriggerPtr> triggers;
        std::list<_EventPtr> events;
        for (size_t i=0; i<_triggers.count; i++) {
            const auto& triggerBase = _triggers.triggers[i];
            switch (triggerBase.type) {
            case Trigger::Type::Time: {
                auto trigger = std::make_unique<_TimeTrigger>();
                trigger->base = &triggerBase;
                
                auto ev = std::make_unique<_TimeTriggerEvent>();
                ev->time = _PastTime(now, triggerBase.time.schedule.time);
                ev->trigger = &*trigger;
                break;
            }
            
            case Trigger::Type::Motion: {
                
                break;
            }
            
            case Trigger::Type::Button: {
                
                break;
            }
            
            default: abort();
            }
        }
        
        {
            auto x = std::make_unique<_BatteryDailySelfDischargeEvent>();
            x->time = time;
            _advance(*x);
            _Insert(events, std::move(x));
        }
        
        {
            auto x = std::make_unique<_StimulusEvent>();
            x->time = time;
            _advance(*x);
            _Insert(events, std::move(x));
        }
        
        for (;;) {
            _EventPtr event = std::move(events.front());
            events.pop_front();
            
            if (auto x = dynamic_cast<_BatteryDailySelfDischargeEvent*>(event.get())) {
                batteryLevel *= 1-_consts.batteryDailySelfDischarge;
                _advance(*x);
            
            } else if (auto x = dynamic_cast<_StimulusEvent*>(event.get())) {
                for (auto& trigger : triggers) {
                    
                }
                _advance(*x);
            
            } else {
                // Unknown type
                abort();
            }
            
            _Insert(events, std::move(event));
            printf("Battery level: %.1f%%\n", batteryLevel*100);
        }
    }
    
    const Constants _consts;
    const Parameters _params;
    const DeviceSettings::Triggers _triggers;
};

//inline std::chrono::seconds BatteryLifeEstimate(const Constants& consts,
//    const Parameters& params, const DeviceSettings::Triggers& triggers) {
//    
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
////    EventPtr a = std::make_unique<BatteryDailySelfDischargeEvent>();
//    
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
//    
//    return std::chrono::seconds(0);
//}

} // namespace MDCStudio::BatteryLifeEstimate
