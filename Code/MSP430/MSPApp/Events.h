#pragma once

// TODO: when we move to using >=C++20, we want to give _State.events as T_Base, but we have to give the whole _State
//       while we're on C++17, because C++17 doesn't allow giving subojects as non-type template parameters.
//       We created _T_Base for this reason, and can remove it and replace all uses with T_Base when we switch.
template<auto& T_Base, typename T_MotionEnabled>
struct T_Events {
    // TODO: write Init() function that initializes Events, and ?????? then implement alt where we don't need an idx ivar because all Events are in an array that reflects its base array, which removes most of Init function. which impl is smaller?
    struct Event {
        enum class Type : uint8_t {
            TimeTrigger,        // idx: _TimeTrigger[]
            CaptureImage,       // idx: _Capture[]
            MotionEnable,       // idx: _MotionTrigger[]
            MotionDisable,      // idx: _MotionTrigger[]
            MotionUnsuppress,   // idx: _MotionTrigger[]
        };
        
//        Event() {} // Necessary to workaround Clang bug that emits compiler error
        Time::Instant instant = 0;
        Event* next = nullptr;
        Type type = Type::TimeTrigger;
        uint8_t idx = 0;
        
        auto& timeTrigger()     { return _TimeTrigger[idx];    }
        auto& motionTrigger()   { return _MotionTrigger[idx];  }
        auto& buttonTrigger()   { return _ButtonTrigger[idx];  }
        auto& capture()         { return _Capture[idx]; }
        auto& base()            { return _Base(_T_Base.event, _Event, *this); }
    };
    
    struct TimeTrigger {
        Event captureEvent = { .type = Event::Type::CaptureImage };
        auto& base() { return _Base(_T_Base.timeTrigger, _TimeTrigger, *this); }
    };
    
    struct MotionTrigger {
        T_MotionEnabled enabled;
        Event captureEvent = { .type = Event::Type::CaptureImage };
        Event unsuppressEvent = { .type = Event::Type::MotionUnsuppress };
        auto& base() { return _Base(_T_Base.motionTrigger, _MotionTrigger, *this); }
    };
    
    struct ButtonTrigger {
        Event captureEvent = { .type = Event::Type::CaptureImage };
        auto& base() { return _Base(_T_Base.buttonTrigger, _ButtonTrigger, *this); }
    };
    
    struct Capture {
//        Capture() {} // Necessary to workaround Clang bug that emits compiler error
        // countRem: remaining number of images to be captured until the current burst is complete
        uint16_t countRem = 0;
        auto& base() { return _Base(_T_Base.capture, _Capture, *this); }
    };
    
    static void Init() {
        for (auto it=TimeTriggerBegin(); it!=TimeTriggerEnd(); it++) {
            it->captureEvent.idx = it->base().captureIdx;
        }
        
        for (auto it=MotionTriggerBegin(); it!=MotionTriggerEnd(); it++) {
            it->captureEvent.idx = it->base().captureIdx;
        }
        
        for (auto it=ButtonTriggerBegin(); it!=ButtonTriggerEnd(); it++) {
            it->captureEvent.idx = it->base().captureIdx;
        }
    }
    
    static void Insert(Event& ev) {
        Event** curr = &_Front;
        Event** prev = curr;
        while (*curr && (ev.instant > (*curr)->instant)) {
            prev = curr;
            curr = &((*curr)->next);
        }
        
        ev.next = (*prev)->next;
        *prev = &ev;
    }
    
    static Event* Pop(const Time::Instant& t) {
        if (!_Front) return nullptr;
        // If the front event occurs after the current time, no events are ready yet.
        if (_Front->instant >= t) return nullptr;
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
    
    static auto EventBegin() { return std::begin(_Event); }
    static auto EventEnd() { return std::begin(_Event)+_T_Base.eventCount; }
    
    static auto CaptureBegin() { return std::begin(_Capture); }
    static auto CaptureEnd() { return std::begin(_Capture)+_T_Base.captureCount; }
    
    static constexpr auto& _T_Base = T_Base.events;
    
    template<typename T_Dst, typename T_Src, size_t T_Count>
    static T_Dst& _Base(T_Dst (&dst)[T_Count], T_Src (&src)[T_Count], T_Src& elm) {
        Assert(&elm>=src && &elm<(src+T_Count));
        const size_t idx = &elm-src;
        return dst[idx];
    }
    
    // Triggers
    static inline TimeTrigger   _TimeTrigger[std::size(_T_Base.timeTrigger)];
    static inline MotionTrigger _MotionTrigger[std::size(_T_Base.motionTrigger)];
    static inline ButtonTrigger _ButtonTrigger[std::size(_T_Base.buttonTrigger)];
    // Events
    static inline Event _Event[std::size(_T_Base.event)];
    // Capture descriptors
    static inline Capture _Capture[std::size(_T_Base.capture)];
    // Event linked list
    static inline Event*  _Front = nullptr;
    
    static constexpr size_t _TotalSize = sizeof(_TimeTrigger)   +
                                         sizeof(_MotionTrigger) +
                                         sizeof(_ButtonTrigger) +
                                         sizeof(_Event)         +
                                         sizeof(_Capture)       +
                                         sizeof(_Front)         ;
};
