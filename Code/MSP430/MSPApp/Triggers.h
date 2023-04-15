#pragma once
#include <cstdlib>
#include "MSP.h"

// TODO: when we move to using >=C++20, we want to give _State.settings.events as T_Base, but we have to give
//       the whole _State while we're on C++17, because C++17 doesn't allow giving subojects as non-type
//       template parameters.
//       We created _T_Base for this reason, and can remove it and replace all uses with T_Base when we switch.
template<
auto& T_Base,
typename T_MotionEnabled,
[[noreturn]] void T_Error(uint16_t)
>
struct T_Triggers {
#define Assert(x) if (!(x)) T_Error(__LINE__)
    struct Trigger;
    
    struct Event {
        enum class Type : uint8_t {
            TimeTrigger,
            MotionEnable,
            MotionDisable,
            MotionUnsuppress,
            CaptureImage,
        };
        
        static Event::Type Convert(MSP::Triggers::Event::Type x) {
            switch (x) {
            case MSP::Triggers::Event::Type::TimeTrigger:  return Type::TimeTrigger;
            case MSP::Triggers::Event::Type::MotionEnable: return Type::MotionEnable;
            }
            Assert(false);
        }
        
        Event(Type type) : type(type) {}
        
        Time::Instant time = 0;
        Event* next = nullptr;
        Type type = Type::TimeTrigger;
    };
    
    struct RepeatEvent : Event {
        RepeatEvent() : Event(Event::Convert(base().type)), repeat(base().repeat) {}
        auto& base() { return _BaseElm(_T_Base.event, _Event, *this); }
        
        MSP::Repeat repeat;
    };
    
    struct TimeTriggerEvent : RepeatEvent {
        auto& trigger() { return _TimeTrigger[RepeatEvent::base().idx]; }
    };
    
    struct MotionEnableEvent : RepeatEvent {
        auto& trigger() { return _MotionTrigger[RepeatEvent::base().idx]; }
    };
    
    struct MotionDisableEvent : Event {
        MotionDisableEvent() : Event(Event::Type::MotionDisable) {}
    };
    
    struct MotionUnsuppressEvent : Event {
        MotionUnsuppressEvent() : Event(Event::Type::MotionUnsuppress) {}
    };
    
    struct CaptureImageEvent : Event {
        CaptureImageEvent(const MSP::Capture& capture) : Event(Event::Type::CaptureImage), capture(&capture) {}
        
        const MSP::Capture* capture = nullptr;
        uint16_t countRem = 0;
    };
    
    struct TimeTrigger : CaptureImageEvent {
        TimeTrigger() : CaptureImageEvent(base().capture) {}
        auto& base() { return _BaseElm(_T_Base.timeTrigger, _TimeTrigger, *this); }
    };
    
    struct MotionTrigger : CaptureImageEvent, MotionDisableEvent, MotionUnsuppressEvent {
        MotionTrigger() : CaptureImageEvent(base().capture) {}
        auto& base() { return _BaseElm(_T_Base.motionTrigger, _MotionTrigger, *this); }
        
        T_MotionEnabled enabled;
    };
    
    struct ButtonTrigger : CaptureImageEvent {
        ButtonTrigger() : CaptureImageEvent(base().capture) {}
        auto& base() { return _BaseElm(_T_Base.buttonTrigger, _ButtonTrigger, *this); }
    };
    
    static void Init(const Time::Instant& t) {
        // Reset _Front since we allow _Init to be called multiple times
        _Front = nullptr;
        
        // If we don't know the absolute time, run in 'relative time mode', where we still
        // execute events with the same relative timing as in 'absolute time mode', we just
        // don't know the absolute time. To do so, we subtract the first event's absolute
        // time from all events, such that the first event starts at Time::Instant=0.
        Time::Instant sub = 0;
        if (!Time::Absolute(t)) {
            sub = _Event[0].base().time;
        }
        
        // Reset T_MotionEnabled's
        for (auto it=MotionTriggerBegin(); it!=MotionTriggerEnd(); it++) {
            it->enabled = {};
        }
        
        // Schedule events
        for (auto it=EventBegin(); it!=EventEnd(); it++) {
            EventInsert(*it, it->base().time-sub);
        }
    }
    
    static void EventInsert(Event& ev, const Time::Instant& t) {
        ev.time = t;
        
        Event** prev = &_Front;
        Event* curr = _Front;
        while (curr && (ev.time > curr->time)) {
            prev = &curr->next;
            curr = curr->next;
        }
        
        *prev = &ev;
        ev.next = curr;
    }
    
    static Event* EventPop(const Time::Instant& t) {
        if (!_Front) return nullptr;
        // If the front event occurs after the current time, no events are ready yet.
        if (_Front->time >= t) return nullptr;
        Event*const f = _Front;
        _Front = f->next;
        return f;
    }
    
    static auto EventBegin() { return std::begin(_Event); }
    static auto EventEnd()   { return std::begin(_Event)+EventCount(); }
    static auto EventCount() { return _T_Base.eventCount; }
    
    static auto TimeTriggerBegin() { return std::begin(_TimeTrigger); }
    static auto TimeTriggerEnd() { return std::begin(_TimeTrigger)+_T_Base.timeTriggerCount; }
    
    static auto MotionTriggerBegin() { return std::begin(_MotionTrigger); }
    static auto MotionTriggerEnd() { return std::begin(_MotionTrigger)+_T_Base.motionTriggerCount; }
    
    static auto ButtonTriggerBegin() { return std::begin(_ButtonTrigger); }
    static auto ButtonTriggerEnd() { return std::begin(_ButtonTrigger)+_T_Base.buttonTriggerCount; }
    
    static constexpr auto& _T_Base = T_Base.settings.triggers;
    using _Base = std::remove_reference_t<decltype(_T_Base)>;
    
    template<typename T_Dst, typename T_Src, size_t T_Count>
    static constexpr T_Dst& _BaseElm(T_Dst (&dst)[T_Count], T_Src (&src)[T_Count], T_Src& elm) {
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
#undef Assert
};
