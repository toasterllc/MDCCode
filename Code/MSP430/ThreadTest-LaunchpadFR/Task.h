#pragma once
#include <optional>
#include "Toastbox/IntState.h"

namespace Toastbox {

class Scheduler {
public:
    using Ticks = unsigned int;
    
    // Run<T_Tasks>(): run the `T_Tasks` list of tasks indefinitely
    template <typename... T_Tasks>
    static void Run() {
        for (;;) {
            do {
                _DidWork = false;
                _Run<T_Tasks...>();
            } while (_DidWork);
            IntState::WaitForInterrupt();
        }
    }
    
    // Yield(): yield current task to the scheduler
    static void Yield() {
        _Yield();
        _StartWork();
    }
    
    // Wait(fn): sleep current task until `fn` returns true
    template <typename T_Fn>
    static auto Wait(T_Fn&& fn) {
        for (;;) {
            // Disable interrupts while we check for work.
            // This is necessary because a previous task may have done work and therefore enabled interrupts.
            // If we were to check for work with interrupts enabled, it's possible to observe WorkNeeded=0
            // but then an interrupt fires immediately after that, generating pending work. But we'd go to
            // sleep because we originally observed WorkNeeded=0, even though if we were to check again,
            // we'd observe WorkNeeded=1. Thus without disabling interrupts, it's possible to go to sleep
            // with pending work, which is bad.
            IntState::SetInterruptsEnabled(false);
            const auto r = fn();
            if (r) {
                _StartWork();
                return r;
            }
            
            _Yield();
        }
    }
    
    // Sleep(ticks): sleep current task for `ticks`
    static void Sleep(Ticks ticks) {
         // Disable interrupts while we update globals
         IntState::SetInterruptsEnabled(false);
         // Calculate when we should wake up
         _CurrentTask->wakeTime = _CurrentTime + ticks + 1;
         // Put the current task at the front of the _SleepTasks linked list
         _CurrentTask->nextSleepTask = _SleepTasks;
         _SleepTasks = _CurrentTask;
         
         for (;;) {
            // Disable interrupts while we check for work.
            // See explanation in Wait().
            IntState::SetInterruptsEnabled(false);
            // We're done sleeping when `wakeTime` is cleared by the ISR
            if (!_CurrentTask->wakeTime) {
                _StartWork();
                return;
            }
            
            _Yield();
         }
    }
    
    // Tick(): notify scheduler that a tick has passed
    // Returns whether any tasks were woken up
    static bool Tick() {
        bool woke = false;
        // Update current time
        _CurrentTime++;
        // Iterate over the sleeping tasks and wake the appropriate ones
        _Task** tprevNext = &_SleepTasks;
        for (_Task* t=_SleepTasks; t; t=t->nextSleepTask) {
            if (*t->wakeTime == _CurrentTime) {
                // Current task should wake, so:
                //   - Clear wakeTime to signal the wake to Sleep()
                //   - Remove current task from _SleepTasks linked list
                t->wakeTime = std::nullopt;
                *tprevNext = t->nextSleepTask;
                woke = true;
            } else {
                // Current task shouldn't wake; just remember its `nextSleepTask` linked list 
                // slot in case the next task needs to be removed from the linked list
                tprevNext = &t->nextSleepTask;
            }
        }
        // Return whether we woke any tasks
        return woke;
    }
    
private:
#define _SPSave(dst)                                                                \
         if constexpr (sizeof(void*) == 2)  asm("mov  r1, %0" : "=m" (dst) : : );   \
    else if constexpr (sizeof(void*) == 4)  asm("mova r1, %0" : "=m" (dst) : : )

#define _SPRestore(src)                                                             \
         if constexpr (sizeof(void*) == 2)  asm("mov  %0, r1" : : "m" (src) : );    \
    else if constexpr (sizeof(void*) == 4)  asm("mova %0, r1" : : "m" (src) : )
    
    struct _Task {
        using _VoidFn = void(*)();
        
        const _VoidFn run = nullptr;
        void* sp = nullptr;
        _VoidFn go = nullptr;
        std::optional<Ticks> wakeTime;
        _Task* nextSleepTask = nullptr;
    };
    
    static inline bool _DidWork = false;
    static inline _Task* _CurrentTask = nullptr;
    static inline _Task* _SleepTasks = nullptr; // Linked list of sleeping tasks
    static inline Ticks _CurrentTime = 0;
    static inline void* _SP = nullptr; // Saved stack pointer
    
    template <typename T_Task, typename... T_Tasks>
    static void _Run() {
        if (_CurrentTask->go) {
            _CurrentTask = &T_Task::_Task;
            _CurrentTask->go();
        }
        if constexpr (sizeof...(T_Tasks)) _Run<T_Tasks...>();
    }
    
    [[gnu::noinline]] // Don't inline: PC must be pushed onto the stack when called
    static void _Start() {
        // Save scheduler stack pointer
        _SPSave(_SP);
        // Restore task stack pointer
        _SPRestore(_CurrentTask->sp);
        
        // Future invocations should execute _Resume()
        _CurrentTask->go = _Resume;
        // Signal that we did work
        _StartWork();
        // Invoke task Run()
        _CurrentTask->run();
        // The task finished
        // Future invocations should do nothing
        _CurrentTask->go = nullptr;
        
        // Restore scheduler stack pointer
        _SPRestore(_SP);
        // Return to scheduler
        return;
    }
    
    [[gnu::noinline]] // Don't inline: PC must be pushed onto the stack when called
    static void _Yield() {
        // Save stack pointer
        _SPSave(_CurrentTask->sp);
        // Restore scheduler stack pointer
        _SPRestore(_SP);
        // Return to scheduler
        return;
    }
    
    [[gnu::noinline]] // Don't inline: PC must be pushed onto the stack when called
    static void _Resume() {
        // Save scheduler stack pointer
        _SPSave(_SP);
        // Restore task stack pointer
        _SPRestore(_CurrentTask->sp);
        // Return to task, to whatever function called _Yield()
        return;
    }
    
    static void _StartWork() {
        _DidWork = true;
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
        _Task.sp = T_Subclass::Stack + sizeof(T_Subclass::Stack);
        _Task.go = Scheduler::_Start;
    }
    
    static void Stop() {
        _Task.go = nullptr;
    }
    
private:
    static inline Scheduler::_Task _Task = {
        .run = T_Subclass::Run,
        .sp = T_Subclass::Stack + sizeof(T_Subclass::Stack),
    };
    
    friend Scheduler;
};

} // namespace Toastbox
