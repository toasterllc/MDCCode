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
    struct Capture : MSP::Capture {
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
        
//        Event() {} // Necessary to workaround Clang bug that emits compiler error
        Time::Instant time = 0;
        Type type = Type::TimeTrigger;
        Trigger* trigger = nullptr;
        Event* next = nullptr;
        
        auto& timeTrigger()   { return *static_cast<TimeTrigger*>(trigger);   }
        auto& motionTrigger() { return *static_cast<MotionTrigger*>(trigger); }
        auto& buttonTrigger() { return *static_cast<ButtonTrigger*>(trigger); }
    };
    
    // TODO: write Init() function that initializes Events, and ?????? then implement alt where we don't need an idx ivar because all Events are in an array that reflects its base array, which removes most of Init function. which impl is smaller?
    struct Trigger {
        Capture capture;
        Event captureEvent = { .type = Event::Type::CaptureImage };
    };
    
    
    
    
    
    struct TimeTrigger : Trigger {
        MSP::Repeat repeat;
        Event triggerEvent = { .type = Event::Type::TimeTrigger };
        auto& base() { return _BaseElm(_T_Base.timeTrigger, _TimeTrigger, *this); }
    };
    
    struct MotionTrigger : Trigger {
        MSP::Repeat repeat;
        T_MotionEnabled enabled;
        Event enableEvent     = { .type = Event::Type::MotionEnable };
        Event disableEvent    = { .type = Event::Type::MotionDisable };
        Event unsuppressEvent = { .type = Event::Type::MotionUnsuppress };
        auto& base() { return _BaseElm(_T_Base.motionTrigger, _MotionTrigger, *this); }
    };
    
    struct ButtonTrigger : Trigger {
        auto& base() { return _BaseElm(_T_Base.buttonTrigger, _ButtonTrigger, *this); }
    };
    
    
    
    static void Init() {
        for (auto it=TimeTriggerBegin(); it!=TimeTriggerEnd(); it++) {
            auto& base = it->base();
            // Init capture
            it->capture = base.capture;
            // Init repeat
            it->repeat = base.repeat;
            // Init events
            it->captureEvent.trigger = &*it;
            it->triggerEvent.trigger = &*it;
            // Schedule
            it->triggerEvent.time = base.time;
        }
        
        for (auto it=MotionTriggerBegin(); it!=MotionTriggerEnd(); it++) {
            auto& base = it->base();
            // Init capture
            it->capture = base.capture;
            // Init repeat
            it->repeat = base.repeat;
            // Init events
            it->captureEvent.trigger = &*it;
            it->enableEvent.trigger = &*it;
            it->disableEvent.trigger = &*it;
            it->unsuppressEvent.trigger = &*it;
            // Schedule
            it->triggerEvent.time = base.time;
        }
        
        for (auto it=ButtonTriggerBegin(); it!=ButtonTriggerEnd(); it++) {
            auto& base = it->base();
            // Init capture
            it->capture = base.capture;
            // Init events
            it->captureEvent.trigger = &*it;
        }
        
        // Prepare events linked list
        {
            Event** prev = &_Front;
            for (auto it=EventBegin(); it!=EventEnd(); it++) {
                Event& ev = *it;
                const _EventBase& bev = it->base();
                
                ev.time = bev.time;
                ev.type = _EventTypeForBaseEventType(bev.type);
                ev.idx = bev.idx;
                
                *prev = &*it;
                prev = &it->next;
            }
        }
    }
    
    static void EventInsert(Event& ev) {
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
    static inline TimeTrigger   _TimeTrigger[std::size(_T_Base.timeTrigger)];
    static inline MotionTrigger _MotionTrigger[std::size(_T_Base.motionTrigger)];
    static inline ButtonTrigger _ButtonTrigger[std::size(_T_Base.buttonTrigger)];
    // Event linked list
    static inline Event* _Front = nullptr;
    
    static constexpr size_t _TotalSize = sizeof(_TimeTrigger)   +
                                         sizeof(_MotionTrigger) +
                                         sizeof(_ButtonTrigger) +
                                         sizeof(_Front)         ;
//    StaticPrint(_TotalSize);
};
