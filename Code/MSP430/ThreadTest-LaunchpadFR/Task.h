#pragma once
#include <optional>
#include "Toastbox/IntState.h"

namespace Toastbox {

template <typename... T_Tasks>
class Scheduler {
public:
    using Ticks = unsigned int;
    
    struct Option {
        struct Start; // Task should start
    };
    
    using MeowFn = void(*)();
    
    template <typename... T_Options>
    struct Options {
        template <typename T_Option>
        static constexpr bool Exists() {
            return (std::is_same_v<T_Option, T_Options> || ...);
        }
    };
    
    #warning make Start/Stop usable from ISRs? eg, if we have a motion task, it
    #warning could be started by the ISR. alternatively it could Wait() on a
    #warning boolean set by an ISR...
    
    template <typename T_Task>
    static void Start() {
        _Task& task = _GetTask<T_Task>();
        task.go = _Start;
    }
    
    template <typename T_Task>
    static void Stop() {
        _Task& task = _GetTask<T_Task>();
        task.go = _Nop;
    }
    
    // Run(): run the tasks indefinitely
    [[noreturn]]
    static void Run() {
        for (;;) {
            do {
                _DidWork = false;
                for (_Task& task : _Tasks) {
                    _CurrentTask = &task;
                    task.go();
                }
            } while (_DidWork);
            
            IntState::WaitForInterrupt();
            #warning interrupts need to be disabled while we inspect them for wakeup eligibility 
            #warning for this to work completely reliably, we should exit WaitForInterrupt/LPM with interrupts disabled
            
            // Check if tasks need to be woken / _WakeTime needs to be updated
            if (_Wake) {
                _Wake = false;
                
                Ticks newWakeTime = 0;
                Ticks newWakeDelay = std::numeric_limits<Ticks>::max();
                
                for (_Task& task : _Tasks) {
                    auto& taskWakeTime = task.wakeTime;
                    if (!taskWakeTime) continue;
                    
                    // If this task needs waking at the current tick, wake it
                    if (*taskWakeTime == _WakeTime) {
                        taskWakeTime = std::nullopt;
                        task.go = _Resume;
                    
                    } else {
                        const Ticks taskWakeDelay = *taskWakeTime-_CurrentTime;
                        if (taskWakeDelay < newWakeDelay) {
                            newWakeTime = *taskWakeTime;
                            newWakeDelay = taskWakeDelay;
                        }
                    }
                }
                
                // Update the next wake time
                _WakeTime = newWakeTime;
            }
        }
    }
    
    // Yield(): yield current task to the scheduler
    static void Yield() {
        _Yield();
        _StartWork();
    }
    
    // Wait(fn): sleep current task until `fn` returns true
    // `fn` must not cause any task to become runnable.
    // If it does, Scheduler may not notice that the task is runnable and
    // could go to sleep instead of running the task.
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
         
         // Update task state
         _CurrentTask->wakeTime = _CurrentTime + ticks + 1;
         _CurrentTask->go = _Nop;
         // Wake immediately so that Run() updates `_WakeTime` properly.
         // This is a cheap hack to minimize the code we emit by keeping the
         // _WakeTime-updating code in one place (Run())
         _Wake = true;
         
         _Yield();
    }
    
    // Tick(): notify scheduler that a tick has passed
    // Returns whether the scheduler needs to run
    static bool Tick() {
        // Update current time
        _CurrentTime++;
        if (_WakeTime == _CurrentTime) {
            _Wake = true;
            return true;
        }
        return false;
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
        void*const spInit = nullptr;
        
        void* sp = nullptr;
        _VoidFn go = nullptr;
        std::optional<Ticks> wakeTime;
    };
    
    [[gnu::noinline]] // Don't inline: PC must be pushed onto the stack when called
    static void _Start() {
        // Prepare the task for execution
        _CurrentTask->sp = _CurrentTask->spInit;
        _CurrentTask->go = _Resume;
        // Clear the task's wakeTime since it's no longer sleeping.
        // Ideally we would re-calculate _WakeTime, but we don't to minimize the emitted code
        _CurrentTask->wakeTime = std::nullopt;
        
        // Save scheduler stack pointer
        _SPSave(_SP);
        // Restore task stack pointer
        _SPRestore(_CurrentTask->sp);
        
        // Signal that we did work
        _StartWork();
        // Invoke task Run()
        _CurrentTask->run();
        // The task finished
        // Future invocations should do nothing
        _CurrentTask->go = _Nop;
        
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
    
    [[gnu::noinline]] // Don't inline: PC must be pushed onto the stack when called
    static void _Nop() {
        // Return to scheduler
        return;
    }
    
    static void _StartWork() {
        _DidWork = true;
        IntState::SetInterruptsEnabled(true);
    }
    
    // _GetTask(): returns the _Task& for the given T_Task
    template <typename T_Task>
    static constexpr _Task& _GetTask() {
        static_assert((std::is_same_v<T_Task, T_Tasks> || ...), "invalid task");
        return _Tasks[_ElmIdx<T_Task, T_Tasks...>()];
    }
    
    template <typename T_1, typename T_2=void, typename... T_s>
    static constexpr size_t _ElmIdx() {
        return std::is_same_v<T_1,T_2> ? 0 : 1 + _ElmIdx<T_1, T_s...>();
    }
    
    template <typename T_Task, typename T_Option>
    static constexpr bool _TaskHasOption() {
        return T_Task::Options::template Exists<T_Option>();
    }
    
    static inline _Task _Tasks[] = {_Task{
        .run    = T_Tasks::Run,
        .spInit = T_Tasks::Stack + sizeof(T_Tasks::Stack),
        .go     = _TaskHasOption<T_Tasks, typename Option::Start>() ? _Start : _Nop,
    }...};
    
    static inline bool _DidWork = false;
    static inline _Task* _CurrentTask = nullptr;
    static inline void* _SP = nullptr; // Saved stack pointer
    
    static inline Ticks _CurrentTime = 0;
    static inline bool _Wake = false;
    static inline Ticks _WakeTime = 0;
    
    class Task;
    friend Task;
    
#undef _SPSave
#undef _SPRestore
};

} // namespace Toastbox
