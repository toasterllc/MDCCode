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
        task.sp = _CurrentTask->spInit;
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
        bool wakeTimeUpdate = false;
        for (;;) {
            do {
                _DidWork = false;
                for (_Task& task : _Tasks) {
                    _CurrentTask = &task;
                    task.go();
                }
            } while (_DidWork);
            
            // Skip sleeping if the wake time needs updating, and
            // therefore we don't know when to wake up yet
            if (_WakeTimeUpdate) goto wakeTasks;
            
            PAOUT &= ~BIT2;
            IntState::WaitForInterrupt();
            PAOUT |= BIT2;
            
            // Check if tasks need to be woken on the current tick
            if (_WakeTime == _CurrentTime) goto wakeTasks;
            continue;
            
            wakeTasks: {
                _WakeTimeUpdate = false;
                
                Ticks newWakeTime = 0;
                Ticks newWakeDelay = std::numeric_limits<Ticks>::max();
                
                for (_Task& task : _Tasks) {
                    auto& taskWakeTime = task.wakeTime;
                    if (!taskWakeTime) continue;
                    
                    // If this task needs to be woken on the current tick, wake it
                    if (*taskWakeTime == _CurrentTime) {
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
                
                _WakeTime = newWakeTime;
            }
            #warning interrupts need to be disabled while we inspect them for wakeup eligibility 
            #warning for this to work completely reliably, we should exit WaitForInterrupt/LPM with interrupts disabled
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
         // Update  immediately so that Run() updates `_WakeTime` properly.
         // This is a cheap hack to minimize the code we emit by keeping the
         // _WakeTime-updating code in one place (Run())
         _WakeTimeUpdate = true;
         
         _Yield();
    }
    
    // Tick(): notify scheduler that a tick has passed
    // Returns whether the scheduler needs to run
    static bool Tick() {
        _CurrentTime++;
        return (_WakeTime == _CurrentTime);
    }
    
private:
#define _SPSave(dst)                                                                \
         if constexpr (sizeof(void*) == 2)  asm("mov  r1, %0" : "=m" (dst) : : );   \
    else if constexpr (sizeof(void*) == 4)  asm("mova r1, %0" : "=m" (dst) : : )

#define _SPRestore(src)                                                             \
         if constexpr (sizeof(void*) == 2)  asm("mov  %0, r1" : : "m" (src) : );    \
    else if constexpr (sizeof(void*) == 4)  asm("mova %0, r1" : : "m" (src) : )

#define _Return()                                                                   \
         if constexpr (sizeof(void*) == 2)  asm("ret" : : : );                      \
    else if constexpr (sizeof(void*) == 4)  asm("reta" : : : )
    
    struct _Task {
        using _VoidFn = void(*)();
        
        const _VoidFn run = nullptr;
        void*const spInit = nullptr;
        
        void* sp = nullptr;
        _VoidFn go = nullptr;
        std::optional<Ticks> wakeTime;
    };
    
    [[gnu::noinline, gnu::naked]] // Don't inline: PC must be pushed onto the stack when called
    static void _Start() {
        // Save scheduler stack pointer
        _SPSave(_SP);
        // Restore task stack pointer
        _SPRestore(_CurrentTask->sp);
        
        _RunCurrentTask();
        
        // Restore scheduler stack pointer
        _SPRestore(_SP);
        // Return to scheduler
        _Return();
    }
    
    static void _RunCurrentTask() {
        // Future invocations should execute _Resume
        _CurrentTask->go = _Resume;
        // Clear the task's wakeTime since it's no longer sleeping.
        // Ideally we'd re-calculate the global _WakeTime, but we don't in order to minimize
        // the emitted code, and just accept that a wake can occur with no tasks that need
        // waking.
        _CurrentTask->wakeTime = std::nullopt;
        // Signal that we did work
        _StartWork();
        // Invoke task Run()
        _CurrentTask->run();
        // The task finished
        // Future invocations should do nothing
        _CurrentTask->go = _Nop;
    }
    
    [[gnu::noinline, gnu::naked]] // Don't inline: PC must be pushed onto the stack when called
    static void _Yield() {
        // Save stack pointer
        _SPSave(_CurrentTask->sp);
        // Restore scheduler stack pointer
        _SPRestore(_SP);
        // Return to scheduler
        _Return();
    }
    
    [[gnu::noinline, gnu::naked]] // Don't inline: PC must be pushed onto the stack when called
    static void _Resume() {
        // Save scheduler stack pointer
        _SPSave(_SP);
        // Restore task stack pointer
        _SPRestore(_CurrentTask->sp);
        // Return to task, to whatever function called _Yield()
        _Return();
    }
    
    [[gnu::noinline, gnu::naked]] // Don't inline: PC must be pushed onto the stack when called
    static void _Nop() {
        // Return to scheduler
        _Return();
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
        .sp     = T_Tasks::Stack + sizeof(T_Tasks::Stack),
        .go     = _TaskHasOption<T_Tasks, typename Option::Start>() ? _Start : _Nop,
    }...};
    
    static inline bool _DidWork = false;
    static inline _Task* _CurrentTask = nullptr;
    static inline void* _SP = nullptr; // Saved stack pointer
    
    static inline Ticks _CurrentTime = 0;
    static inline Ticks _WakeTime = 0;
    static inline bool _WakeTimeUpdate = false;
    
    class Task;
    friend Task;
    
#undef _SPSave
#undef _SPRestore
};

} // namespace Toastbox
