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
    
    template <typename... T_Options>
    struct Options {
        template <typename T_Option>
        static constexpr bool Exists() {
            return (std::is_same_v<T_Option, T_Options> || ...);
        }
    };
    
    template <typename T_Task>
    static void Start() {
        _Task& task = _GetTask<T_Task>();
        task.sp = _CurrentTask->spInit;
        task.go = _TaskStart;
    }
    
    template <typename T_Task>
    static void Stop() {
        _Task& task = _GetTask<T_Task>();
        task.go = _TaskNop;
    }
    
    // Run(): run the tasks indefinitely
    [[noreturn]]
    static void Run() {
        for (;;) {
            do {
                IntState::SetInterruptsEnabled(false);
                
                _DidWork = false;
                for (_Task& task : _Tasks) {
                    _CurrentTask = &task;
                    task.go();
                }
            } while (_DidWork);
            
            // Reset _Wake now that we're assured that every task has been able to observe
            // _Wake=true while interrupts were disabled during the entire process.
            _Wake = false;
            
            // No work to do
            // Go to sleep!
            IntState::WaitForInterrupt();
        }
    }
    
    // Yield(): yield current task to the scheduler
    static void Yield() {
        _TaskPause();
        _TaskStartWork();
    }
    
    // Wait(fn): sleep current task until `fn` returns true
    // `fn` must not cause any task to become runnable.
    // If it does, the scheduler may not notice that the task is runnable and
    // could go to sleep instead of running the task.
    template <typename T_Fn>
    static auto Wait(T_Fn&& fn) {
        for (;;) {
            const auto r = fn();
            if (!r) {
                _TaskPause();
                continue;
            }
            
            _TaskStartWork();
            return r;
        }
    }
    
    // Sleep(ticks): sleep current task for `ticks`
    static void Sleep(Ticks ticks) {
        const Ticks wakeTime = _CurrentTime+ticks+1;
        do {
            // Update _WakeTime
            const Ticks wakeDelay = wakeTime-_CurrentTime;
            const Ticks currentWakeDelay = _WakeTime-_CurrentTime;
            if (!currentWakeDelay || wakeDelay < currentWakeDelay) {
                _WakeTime = wakeTime;
            }
            
            // Wait until some task wakes
            do _TaskPause();
            while (!_Wake);
        
        } while (_CurrentTime != wakeTime);
        
        _TaskStartWork();
    }
    
    // Tick(): notify scheduler that a tick has passed
    // Returns whether the scheduler needs to run
    static bool Tick() {
        // Don't increment time if there's an existing _Wake signal that hasn't been consumed.
        // This is necessary so that we don't miss any ticks, which could cause a task wakeup to be missed.
        if (_Wake) return true;
        
        _CurrentTime++;
        if (_CurrentTime == _WakeTime) {
            _Wake = true;
            return true;
        }
        
        return false;
    }
    
private:
#define _RegsSave()                                                                         \
         if constexpr (sizeof(void*) == 2)  asm("pushm   #7, r10" : : : );                  \
    else if constexpr (sizeof(void*) == 4)  asm("pushm.a #7, r10" : : : )

#define _RegsRestore()                                                                      \
         if constexpr (sizeof(void*) == 2)  asm("popm   #7, r10" : : : );                   \
    else if constexpr (sizeof(void*) == 4)  asm("popm.a #7, r10" : : : )

#define _PCRestore()                                                                        \
         if constexpr (sizeof(void*) == 2)  asm volatile("ret " : : : );                    \
    else if constexpr (sizeof(void*) == 4)  asm volatile("reta" : : : )

#define _SPSave(dst)                                                                        \
         if constexpr (sizeof(void*) == 2)  asm volatile("mov  r1, %0" : "=m" (dst) : : );  \
    else if constexpr (sizeof(void*) == 4)  asm volatile("mova r1, %0" : "=m" (dst) : : )

#define _SPRestore(src)                                                                     \
         if constexpr (sizeof(void*) == 2)  asm volatile("mov  %0, r1" : : "m" (src) : );   \
    else if constexpr (sizeof(void*) == 4)  asm volatile("mova %0, r1" : : "m" (src) : )
    
    struct _Task {
        using _VoidFn = void(*)();
        
        const _VoidFn run = nullptr;
        void*const spInit = nullptr;
        
        void* sp = nullptr;
        _VoidFn go = nullptr;
        Ticks sleepTotal = 0;
        Ticks sleepCount = 0;
    };
    
    [[gnu::noinline, gnu::naked]] // Don't inline: PC must be pushed onto the stack when called
    static void _TaskStart() {
        // Save scheduler regs
        _RegsSave();
        // Save scheduler SP
        _SPSave(_SP);
        // Restore task SP
        _SPRestore(_CurrentTask->sp);
        // Run task
        _TaskRun();
        // Restore scheduler SP
        _SPRestore(_SP);
        // Restore scheduler regs
        _RegsRestore();
        // Restore scheduler PC
        _PCRestore();
    }
    
    static void _TaskRun() {
        // Future invocations should execute _TaskResume
        _CurrentTask->go = _TaskResume;
        // Signal that we did work
        _TaskStartWork();
        // Invoke task Run()
        _CurrentTask->run();
        // The task finished
        // Future invocations should do nothing
        _CurrentTask->go = _TaskNop;
    }
    
    [[gnu::noinline, gnu::naked]] // Don't inline: PC must be pushed onto the stack when called
    static void _TaskPause() {
        // Save task regs
        _RegsSave();
        // Save task SP
        _SPSave(_CurrentTask->sp);
        // Disable interrupts
        // This balances enabling interrupts in _TaskStartWork(), which may or may not have been called.
        // Regardless, when returning to the scheduler, interrupts need to be disabled.
        IntState::SetInterruptsEnabled(false);
        // Restore scheduler SP
        _SPRestore(_SP);
        // Restore scheduler regs
        _RegsRestore();
        // Restore scheduler PC
        _PCRestore();
    }
    
    [[gnu::noinline, gnu::naked]] // Don't inline: PC must be pushed onto the stack when called
    static void _TaskResume() {
        // Save scheduler regs
        _RegsSave();
        // Save scheduler SP
        _SPSave(_SP);
        // Restore task SP
        _SPRestore(_CurrentTask->sp);
        // Restore task regs
        _RegsRestore();
        // Restore task PC
        _PCRestore();
    }
    
    static void _TaskNop() {
        // Return to scheduler
        return;
    }
    
    static void _TaskStartWork() {
        _DidWork = true;
        // Enable interrupts
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
        .go     = _TaskHasOption<T_Tasks, typename Option::Start>() ? _TaskStart : _TaskNop,
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
