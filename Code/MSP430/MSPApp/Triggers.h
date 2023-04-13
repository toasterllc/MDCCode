#pragma once
#include <cstdlib>
#include "MSP.h"

// TODO: when we move to using >=C++20, we want to give _State.settings.events as T_Base, but we have to give
//       the whole _State while we're on C++17, because C++17 doesn't allow giving subojects as non-type
//       template parameters.
//       We created _T_Base for this reason, and can remove it and replace all uses with T_Base when we switch.
template<auto& T_Base, typename T_MotionEnabled>
struct T_Triggers {
    struct Trigger;
    
    struct Capture {
        const MSP::Capture* capture = nullptr;
        uint16_t countRem = 0;
    };
    
    struct Event {
        enum class Type : uint8_t {
            TimeTrigger,
            MotionEnable,
            MotionDisable,
            MotionUnsuppress,
            CaptureImage,
        };
        
        Event(Type t) : type(t) {}
        
        Time::Instant time = 0;
        Event* next = nullptr;
        Type type = Type::TimeTrigger;
    };
    
//    template<typename Event::Type T_Init>
//    struct T_Event : Event {
//        T_Event() : Event{ .type=T_Init } {}
////        template<typename T>
////        operator T&() { return (T&)*this; }
//    };
    
    struct RepeatEvent : Event {
        using Event::Event;
        MSP::Repeat repeat;
        auto& base() { return _BaseElm(_T_Base.event, _Event, *this); }
    };
    
    struct TimeTriggerEvent : RepeatEvent {
        TimeTriggerEvent() : RepeatEvent(Event::Type::TimeTrigger) {}
        auto& trigger() { return _TimeTrigger[base().idx]; }
    };
    
    struct MotionEnableEvent : RepeatEvent {
        MotionEnableEvent() : RepeatEvent(Event::Type::MotionEnable) {}
        auto& trigger() { return _MotionTrigger[base().idx]; }
    };
    
    struct MotionDisableEvent : Event {
        MotionDisableEvent() : Event(Event::Type::MotionDisable) {}
    };
    
    struct MotionUnsuppressEvent : Event {
        MotionUnsuppressEvent() : Event(Event::Type::MotionUnsuppress) {}
    };
    
    struct CaptureImageEvent : Event {
        CaptureImageEvent() : Event(Event::Type::CaptureImage) {}
        const MSP::Capture* capture = nullptr;
        uint16_t countRem = 0;
    };
    
    struct TimeTrigger {
        CaptureImageEvent captureImageEvent;
        auto& base() { return _BaseElm(_T_Base.timeTrigger, _TimeTrigger, *this); }
    };
    
    struct MotionTrigger {
        T_MotionEnabled enabled;
        CaptureImageEvent captureImageEvent;
        MotionDisableEvent motionDisableEvent;
        MotionUnsuppressEvent motionUnsuppressEvent;
        auto& base() { return _BaseElm(_T_Base.motionTrigger, _MotionTrigger, *this); }
    };
    
    struct ButtonTrigger {
        CaptureImageEvent captureImageEvent;
        auto& base() { return _BaseElm(_T_Base.buttonTrigger, _ButtonTrigger, *this); }
    };
    
//    static TimeTrigger& TriggerCast(TimeTriggerEvent& ev) { return (TimeTrigger&)ev; }
//    static MotionTrigger& TriggerCast(MotionEnableEvent& ev) { return (MotionTrigger&)ev; }
//    static MotionTrigger& TriggerCast(MotionDisableEvent& ev) { return (MotionTrigger&)ev; }
//    static MotionTrigger& TriggerCast(MotionUnsuppressEvent& ev) { return (MotionTrigger&)ev; }
    
    static void Init() {
        for (auto it=TimeTriggerBegin(); it!=TimeTriggerEnd(); it++) {
            auto& base = it->base();
            // Init repeat
            it->repeat = base.repeat;
            // Init capture
            it->capture = base.capture;
            // Schedule TimeTriggerEvent
            EventInsert(*(TimeTriggerEvent*)it, base.time);
        }
        
        for (auto it=MotionTriggerBegin(); it!=MotionTriggerEnd(); it++) {
            auto& base = it->base();
            // Init repeat
            it->repeat = base.repeat;
            // Init capture
            it->capture = base.capture;
            // Schedule MotionEnableEvent
            EventInsert(*(MotionEnableEvent*)it, base.time);
        }
        
        for (auto it=ButtonTriggerBegin(); it!=ButtonTriggerEnd(); it++) {
            auto& base = it->base();
            // Init capture
            ((CaptureImageEvent&)*it).capture = base.capture;
        }
    }
    
    static void EventInsert(Event& ev, const Time::Instant& t) {
        ev.time = t;
        
        Event** curr = &_Front;
        Event** prev = curr;
        while (*curr && (ev.time > (*curr)->time)) {
            prev = curr;
            curr = &((*curr)->next);
        }
        
        ev.next = (*prev)->next;
        *prev = &ev;
    }
    
    static Event* EventPop(const Time::Instant& t) {
        if (!_Front) return nullptr;
        // If the front event occurs after the current time, no events are ready yet.
        if (_Front->time >= t) return nullptr;
        Event*const f = _Front;
        _Front = f->next;
        return f;
    }
    
    static auto TimeTriggerBegin() { return std::begin(_TimeTrigger); }
    static auto TimeTriggerEnd() { return std::begin(_TimeTrigger)+_T_Base.timeTriggerCount; }
    
    static auto MotionTriggerBegin() { return std::begin(_MotionTrigger); }
    static auto MotionTriggerEnd() { return std::begin(_MotionTrigger)+_T_Base.motionTriggerCount; }
    
    static auto ButtonTriggerBegin() { return std::begin(_ButtonTrigger); }
    static auto ButtonTriggerEnd() { return std::begin(_ButtonTrigger)+_T_Base.buttonTriggerCount; }
    
    static constexpr auto& _T_Base = T_Base.settings.triggers;
    using _Base = std::remove_reference_t<decltype(_T_Base)>;
    
    template<typename T_Dst, typename T_Src, size_t T_Count>
    static T_Dst& _BaseElm(T_Dst (&dst)[T_Count], T_Src (&src)[T_Count], T_Src& elm) {
        Assert(&elm>=src && &elm<(src+T_Count));
        const size_t idx = &elm-src;
        return dst[idx];
    }
    
    // Triggers
    static inline RepeatEvent   _Event[std::size(_T_Base.event)];
    static inline TimeTrigger   _TimeTrigger[std::size(_T_Base.timeTrigger)];
    static inline MotionTrigger _MotionTrigger[std::size(_T_Base.motionTrigger)];
    static inline ButtonTrigger _ButtonTrigger[std::size(_T_Base.buttonTrigger)];
    // Event linked list
    static inline Event* _Front = nullptr;
    
    static constexpr size_t _TotalSize = sizeof(_Event)         +
                                         sizeof(_TimeTrigger)   +
                                         sizeof(_MotionTrigger) +
                                         sizeof(_ButtonTrigger) +
                                         sizeof(_Front)         ;
//    StaticPrint(_TotalSize);
};
