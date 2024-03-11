#pragma once
#include <cstdlib>
#include "Code/Shared/MSP.h"
#include "Code/Shared/Time.h"
#include "Code/Shared/TimeConstants.h"
#include "Code/Shared/Assert.h"

// TODO: when we move to using >=C++20, we want to give _State.settings.events as T_Base, but we have to give
//       the whole _State while we're on C++17, because C++17 doesn't allow giving subojects as non-type
//       template parameters.
//       We created _T_Base for this reason, and can remove it and replace all uses with T_Base when we switch.
template<
auto& T_Base,
typename T_MotionPowered
>
struct T_MSPTriggers {
    struct Trigger;
    static constexpr auto& _T_Base = T_Base.settings.triggers;
    using _Base = std::remove_reference_t<decltype(_T_Base)>;
    
    struct Event {
        enum class Type : uint8_t {
            TimeTrigger,
            
            MotionEnablePower,
            MotionEnable,
            MotionDisable,
            
            MotionUnsuppressPower,
            MotionUnsuppress,
            
            CaptureImage,
            
            DSTStart,
            DSTEnd,
        };
        
        static Event::Type Convert(MSP::Triggers::Event::Type x) {
            switch (x) {
            case MSP::Triggers::Event::Type::TimeTrigger:   return Type::TimeTrigger;
            case MSP::Triggers::Event::Type::MotionEnable:  return Type::MotionEnable;
            }
            Assert(false);
        }
        
        Event() = default;
        Event(Type type) : time(0), next(nullptr), type(type) {}
        
        Time::Instant time;
        Event* next;
        Type type;
        
        bool scheduled() const {
            return next != nullptr;
        }
    };
    
    struct RepeatEvent : Event {
        RepeatEvent() = default;
        RepeatEvent(typename _Base::Event& b) : Event(Event::Convert(b.type)), repeat(b.repeat) {}
        auto& base() { return _BaseElm(_T_Base.event, _Event, *this); }
        
        MSP::Repeat repeat;
    };
    
    struct TimeTriggerEvent : RepeatEvent {
        auto& trigger() { return _TimeTrigger[RepeatEvent::base().idx]; }
    };
    
    struct MotionEnableEvent : RepeatEvent {
        auto& trigger() { return _MotionTrigger[RepeatEvent::base().idx]; }
    };
    
    
    
    
    struct MotionEnablePowerEvent : Event {
        MotionEnablePowerEvent() : Event(Event::Type::MotionEnablePower) {}
    };
    
    struct MotionDisableEvent : Event {
        MotionDisableEvent() : Event(Event::Type::MotionDisable) {}
    };
    
    
    
    struct MotionUnsuppressPowerEvent : Event {
        MotionUnsuppressPowerEvent() : Event(Event::Type::MotionUnsuppressPower) {}
    };
    
    struct MotionUnsuppressEvent : Event {
        MotionUnsuppressEvent() : Event(Event::Type::MotionUnsuppress) {}
    };
    
    
    
    
    struct CaptureImageEvent : Event {
        CaptureImageEvent() = default;
        CaptureImageEvent(const MSP::Capture& capture) :
            Event(Event::Type::CaptureImage), capture(&capture), countRem(0) {}
        
        const MSP::Capture* capture;
        uint16_t countRem;
    };
    
    struct TimeTrigger : CaptureImageEvent {
        TimeTrigger() = default;
        TimeTrigger(typename _Base::TimeTrigger& b) : CaptureImageEvent(b.capture) {}
        auto& base() { return _BaseElm(_T_Base.timeTrigger, _TimeTrigger, *this); }
    };
    
    struct MotionTrigger :
        CaptureImageEvent,
        MotionEnablePowerEvent, MotionDisableEvent,
        MotionUnsuppressPowerEvent, MotionUnsuppressEvent {
        
        using State = uint8_t;
        static constexpr State StatePowerEnable     = 1<<0;
        static constexpr State StatePowerSuppress   = 1<<1;
        static constexpr State StateMotionEnable    = 1<<2;
        static constexpr State StateMotionSuppress  = 1<<3;
        static constexpr State StateMaxImageCount   = 1<<4;
        
        MotionTrigger() = default;
        MotionTrigger(typename _Base::MotionTrigger& b) : CaptureImageEvent(b.capture), state(0), countRem(0) {}
        auto& base() { return _BaseElm(_T_Base.motionTrigger, _MotionTrigger, *this); }
        
        static constexpr bool _Enabled(State x) {
            return x == (StatePowerEnable|StateMotionEnable);
        }
        
        static constexpr bool _Powered(State x) {
            return (x & StatePowerEnable) && !(x & (StatePowerSuppress|StateMaxImageCount));
        }
        
        bool enabled() const {
            return _Enabled(state);
        }
        
        void enable() {
            // Enable power / motion
            // Include StatePowerEnable to power on the motion sensor, because it may not be powered already,
            // because the very first MotionEnableEvent doesn't have a corresponding MotionEnablePowerEvent,
            // because we schedule the MotionEnablePowerEvent as a result of the MotionEnableEvent, below.
            stateUpdate(
                StatePowerEnable|StateMotionEnable,
                StateMaxImageCount
            );
            countRem = base().count;
        }
        
        void disable() {
            // Disable power / motion
            stateUpdate(
                0,
                StatePowerEnable|StateMotionEnable
            );
        }
        
        void enablePower() {
            // Enable power
            stateUpdate(
                StatePowerEnable,
                0
            );
        }
        
        void suppress() {
            // Suppress power / motion
            stateUpdate(
                StatePowerSuppress|StateMotionSuppress,
                0
            );
        }
        
        void unsuppress() {
            // Unsuppress power / motion
            stateUpdate(
                0,
                StatePowerSuppress|StateMotionSuppress
            );
        }
        
        void unsuppressPower() {
            // Unsuppress power
            stateUpdate(
                0,
                StatePowerSuppress
            );
        }
        
        void unsuppressMotion() {
            // Unsuppress motion
            stateUpdate(
                0,
                StateMotionSuppress
            );
        }
        
        void hitMaxImageCount() {
            stateUpdate(
                StateMaxImageCount,
                0
            );
        }
        
        [[gnu::noinline]]
        void stateUpdate(State set, State clear) {
            state |= set;
            state &= ~clear;
            powered = _Powered(state);
        }
        
        State state;
        T_MotionPowered powered;
        uint16_t countRem;
    };
    
    struct ButtonTrigger : CaptureImageEvent {
        ButtonTrigger() = default;
        ButtonTrigger(typename _Base::ButtonTrigger& b) : CaptureImageEvent(b.capture) {}
        auto& base() { return _BaseElm(_T_Base.buttonTrigger, _ButtonTrigger, *this); }
    };
    
    static void Init(const Time::Instant& t) {
        // Reset everything
        _Front = _End;
        for (auto& x : _Event)          x = RepeatEvent(x.base());
        for (auto& x : _TimeTrigger)    x = TimeTrigger(x.base());
        for (auto& x : _MotionTrigger)  x = MotionTrigger(x.base());
        for (auto& x : _ButtonTrigger)  x = ButtonTrigger(x.base());
        
        // If we don't know the absolute time, run in 'relative time mode', where we still
        // execute events with the same relative timing as in 'absolute time mode', we just
        // don't know the absolute time. To do so, we subtract the first event's absolute
        // time from all events, such that the first event starts at Time::Instant=0.
        Time::Instant sub = 0;
        if (!Time::Absolute(t)) {
            sub = _Event[0].base().time;
        }
        
        // Schedule events
        for (auto it=EventBegin(); it!=EventEnd(); it++) {
            EventInsert(*it, it->base().time-sub);
        }
    }
    
    static void EventInsert(Event& ev, const Time::Instant& t) {
        EventPop(ev);
        ev.time = t;
        
        Event** prev = &_Front;
        Event* curr = _Front;
        while (curr!=_End && (ev.time > curr->time)) {
            prev = &curr->next;
            curr = curr->next;
        }
        
        *prev = &ev;
        ev.next = curr;
    }
    
    static void EventPop() {
        Assert(_Front != _End);
        EventPop(*_Front);
    }
    
    // EventPop(): remove event from linked list
    static void EventPop(Event& ev) {
        // Only pop the event if we know it's in the list, to avoid having to search
        // for it (since we're using a singly-linked list to save memory).
        if (!ev.scheduled()) return;
        
        Event** prev = &_Front;
        Event* curr = _Front;
        while (curr!=_End && curr!=&ev) {
            prev = &curr->next;
            curr = curr->next;
        }
        Assert(curr);
        
        *prev = ev.next;
        ev.next = nullptr;
    }
    
    static Event* EventFront() {
        if (_Front == _End) return nullptr;
        return _Front;
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
    
    static Time::Ticks32 RepeatAdvance(MSP::Repeat& x) {
        static constexpr Time::Ticks32 YearPlusDay = Time::Year+Time::Day;
        
        switch (x.type) {
        case MSP::Repeat::Type::Never:
            return 0;
        
        case MSP::Repeat::Type::Daily:
            Assert(x.Daily.interval);
            return Time::Day*x.Daily.interval;
        
        case MSP::Repeat::Type::Weekly: {
            #warning TODO: verify this works properly
            // Determine the next trigger day, calculating the duration of time until then
            Assert(x.Weekly.days & 1); // Weekly.days must always rest on an active day
            x.Weekly.days |= 0x80;
            uint8_t count = 0;
            do {
                x.Weekly.days >>= 1;
                count++;
            } while (!(x.Weekly.days & 1));
            return count*Time::Day;
        }
        
        case MSP::Repeat::Type::Yearly:
            #warning TODO: verify this works properly
            // Return 1 year (either 365 or 366 days) in microseconds
            // We appropriately handle leap years by referencing `leapPhase`
            if (x.Yearly.leapPhase) {
                x.Yearly.leapPhase--;
                return Time::Year;
            } else {
                x.Yearly.leapPhase = 3;
                return YearPlusDay;
            }
        }
        Assert(false);
    }
    
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
    // _End: a sentinel value representing the end of the linked list.
    // We use nullptr to mean 'not present in linked list', while _End represents the end of the
    // list (so LastEvent.next==_End).
    // Ideally _End would be `static constexpr` instead of `static inline`, but C++ doesn't allow
    // constexpr reinterpret_cast. In C++20 we could use std::bit_cast for this.
    static inline Event*const _End = (Event*)0x0001;
    static inline Event* _Front;
    
    static constexpr size_t _TotalSize = sizeof(_Event)         +
                                         sizeof(_TimeTrigger)   +
                                         sizeof(_MotionTrigger) +
                                         sizeof(_ButtonTrigger) +
                                         sizeof(_Front)         ;
//    StaticPrint(_TotalSize);
};
