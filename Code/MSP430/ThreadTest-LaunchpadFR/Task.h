#pragma once
#include <optional>
#include "Toastbox/IntState.h"

namespace Toastbox {

using Ticks = unsigned int;

struct _TaskState {
    using VoidFn = void(*)();
    
    const VoidFn run = nullptr;
    void* sp = nullptr;
    VoidFn go = nullptr;
    std::optional<Ticks> wakeTime;
    _TaskState* nextSleeper = nullptr;
    
    static inline bool DidWork = false;
    static inline _TaskState* CurrentTask = nullptr; // Current task _TaskState
    static inline _TaskState* SleepingTasks = nullptr; // Linked list of sleeping tasks
    static inline Ticks CurrentTime = 0;
    static inline void* SP = nullptr; // Saved stack pointer
};

class Scheduler {
#define _SPSave(dst)                                                                \
         if constexpr (sizeof(void*) == 2)  asm("mov  r1, %0" : "=m" (dst) : : );   \
    else if constexpr (sizeof(void*) == 4)  asm("mova r1, %0" : "=m" (dst) : : )

#define _SPRestore(src)                                                             \
         if constexpr (sizeof(void*) == 2)  asm("mov  %0, r1" : : "m" (src) : );    \
    else if constexpr (sizeof(void*) == 4)  asm("mova %0, r1" : : "m" (src) : )
    
public:
    // rule: if interrupts are ever enabled during a scheduler iteration, then work must be considered having been done
    template <typename... T_Tasks>
    static void Run() {
        for (;;) {
            do {
                IntState::SetInterruptsEnabled(false);
                _TaskState::DidWork = false;
                _Run<T_Tasks...>();
            } while (_TaskState::DidWork);
            IntState::WaitForInterrupt();
            IntState::SetInterruptsEnabled(true);
        }
    }
    
    static void Yield() {
        _Yield();
        _StartWork();
    }
    
    template <typename T_Fn>
    static auto Wait(T_Fn&& fn) {
        for (;;) {
            // Disable interrupts while we check for work.
            // This is necessary in addition to disabling interrupts in <T_Tasks>Run(), because a previous
            // task may have done work and therefore enabled interrupts.
            // If we were to check for work with interrupts enabled, it's possible to observe WorkNeeded=0
            // but have an interrupt fire immediately after that causes WorkNeeded=1. We'd then go to
            // sleep because we originally observed WorkNeeded=0, even though if we were to check again,
            // we'd observe WorkNeeded=1. Thus we'd go to sleep with work pending work.
            IntState::SetInterruptsEnabled(false);
            const auto r = fn();
            if (r) {
                _StartWork();
                return r;
            }
            
            _Yield();
        }
    }
    
    static void Sleep(Ticks ticks) {
         if (!ticks) return;
         
         // Disable interrupts while we update globals
         IntState::SetInterruptsEnabled(false);
         // Calculate when we should wake up
         _TaskState::CurrentTask->wakeTime = _TaskState::CurrentTime + ticks;
         // Put the current task at the front of the SleepingTasks list
         _TaskState::CurrentTask->nextSleeper = _TaskState::SleepingTasks;
         _TaskState::SleepingTasks = _TaskState::CurrentTask;
         
         for (;;) {
            // Disable interrupts while we check for work.
            // See explanation in Wait().
            IntState::SetInterruptsEnabled(false);
            // We're done sleeping when `wakeTime` is cleared (by the ISR)
            if (!_TaskState::CurrentTask->wakeTime) {
                _StartWork();
                return;
            }
            
            _Yield();
         }
    }
    
private:
    template <typename T_Task, typename... T_Tasks>
    static void _Run() {
        if (_TaskState::CurrentTask->go) {
            _TaskState::CurrentTask = &T_Task::_State;
            _TaskState::CurrentTask->go();
        }
        if constexpr (sizeof...(T_Tasks)) _Run<T_Tasks...>();
    }
    
    [[gnu::noinline]] // Don't inline: PC must be pushed onto the stack when called
    static void _Start() {
        // Save scheduler stack pointer
        _SPSave(_TaskState::SP);
        // Restore task stack pointer
        _SPRestore(_TaskState::CurrentTask->sp);
        
        // Future invocations should execute _Resume()
        _TaskState::CurrentTask->go = _Resume;
        // Signal that we did work
        _StartWork();
        // Invoke task Run()
        _TaskState::CurrentTask->run();
        // The task finished
        // Future invocations should do nothing
        _TaskState::CurrentTask->go = nullptr;
        
        // Restore scheduler stack pointer
        _SPRestore(_TaskState::SP);
        // Return to scheduler
        return;
    }
    
    [[gnu::noinline]] // Don't inline: PC must be pushed onto the stack when called
    static void _Yield() {
        // Save stack pointer
        _SPSave(_TaskState::CurrentTask->sp);
        // Restore scheduler stack pointer
        _SPRestore(_TaskState::SP);
        // Return to scheduler
        return;
    }
    
    [[gnu::noinline]] // Don't inline: PC must be pushed onto the stack when called
    static void _Resume() {
        // Save scheduler stack pointer
        _SPSave(_TaskState::SP);
        // Restore task stack pointer
        _SPRestore(_TaskState::CurrentTask->sp);
        // Return to task, to whatever function called _Yield()
        return;
    }
    
    static void _StartWork() {
        _TaskState::DidWork = true;
        IntState::SetInterruptsEnabled(true);
    }
    
    class Task;
    friend Task;
    
#undef _SPSave
#undef _SPRestore
};

template <typename T_Subclass>
class Task {
public:
    static void Start() {
        _State.sp = T_Subclass::Stack + sizeof(T_Subclass::Stack);
        _State.go = Scheduler::_Start;
    }
    
    static void Stop() {
        _State.go = nullptr;
    }
    
private:
    static inline _TaskState _State = {
        .run = T_Subclass::Run,
        .sp = T_Subclass::Stack + sizeof(T_Subclass::Stack),
    };
    
    friend Scheduler;
};

} // namespace Toastbox
