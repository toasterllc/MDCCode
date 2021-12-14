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
        for (;;) {
            do {
                // Disable interrupts at the beginning of every iteration, so that if _DidWork=false
                // at the end of our loop, we know that:
                // 
                //   1. no task had work to do, and
                //   2. interrupts were disabled for the duration of every task checking for work.
                // 
                // therefore we can safely go to sleep since we've verified that there's no work to
                // do in a race-free manner.
                
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
            
//            // Update _SleepTask
//            if (_SleepTask && !_SleepTask->sleepCount) {
//                for (_Task& task : _Tasks) {
//                    auto& taskWakeTime = task.wakeTime;
//                    if (!taskWakeTime) continue;
//                    
//                    // If this task needs to be woken on the current tick, wake it
//                    if (*taskWakeTime == _CurrentTime) {
//                        taskWakeTime = std::nullopt;
//                        task.go = _Resume;
//                    
//                    } else {
//                        const Ticks taskWakeDelay = *taskWakeTime-_CurrentTime;
//                        if (taskWakeDelay < newWakeDelay) {
//                            newWakeTime = *taskWakeTime;
//                            newWakeDelay = taskWakeDelay;
//                        }
//                    }
//                }
//            }
            
            
            #warning try 2 different strategies to check whether a task woke:
            #warning   - set _Wake flag in ISR
            #warning   - check `_SleepTask && !_SleepTask->sleepCount`
            
//            // Update _SleepTask
//            if (_SleepTask && !_SleepTask->sleepCount) {
//                for (_Task& task : _Tasks) {
//                    auto& taskWakeTime = task.wakeTime;
//                    if (!taskWakeTime) continue;
//                    
//                    // If this task needs to be woken on the current tick, wake it
//                    if (*taskWakeTime == _CurrentTime) {
//                        taskWakeTime = std::nullopt;
//                        task.go = _Resume;
//                    
//                    } else {
//                        const Ticks taskWakeDelay = *taskWakeTime-_CurrentTime;
//                        if (taskWakeDelay < newWakeDelay) {
//                            newWakeTime = *taskWakeTime;
//                            newWakeDelay = taskWakeDelay;
//                        }
//                    }
//                }
//            }
            
//            // Skip sleeping if the wake time needs updating, and
//            // therefore we don't know when to wake up yet
//            if (_WakeTimeUpdate) goto wakeTasks;
//            
//            #warning try 2 different strategies:
//            #warning   - use _Wake flag for ISR to signal that WakeCounter hit 0
//            #warning   - use local bool to detect WakeCounter 1->0
//            
//            PAOUT &= ~BIT2;
//            IntState::WaitForInterrupt();
//            PAOUT |= BIT2;
//            
//            // Check if tasks need to be woken on the current tick
//            if (_WakeTime == _CurrentTime) goto wakeTasks;
//            continue;
//            
//            wakeTasks: {
//                _WakeTimeUpdate = false;
//                
//                Ticks newWakeTime = 0;
//                Ticks newWakeDelay = std::numeric_limits<Ticks>::max();
//                
//                for (_Task& task : _Tasks) {
//                    auto& taskWakeTime = task.wakeTime;
//                    if (!taskWakeTime) continue;
//                    
//                    // If this task needs to be woken on the current tick, wake it
//                    if (*taskWakeTime == _CurrentTime) {
//                        taskWakeTime = std::nullopt;
//                        task.go = _Resume;
//                    
//                    } else {
//                        const Ticks taskWakeDelay = *taskWakeTime-_CurrentTime;
//                        if (taskWakeDelay < newWakeDelay) {
//                            newWakeTime = *taskWakeTime;
//                            newWakeDelay = taskWakeDelay;
//                        }
//                    }
//                }
//                
//                _WakeTime = newWakeTime;
//            }
//            #warning interrupts need to be disabled while we inspect them for wakeup eligibility 
//            #warning for this to work completely reliably, we should exit WaitForInterrupt/LPM with interrupts disabled
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
            if (!r) {
                _Yield();
                continue;
            }
            
            _StartWork();
            return r;
        }
    }
    
    static void _UpdateWakeTime(Ticks wakeTime) {
        const Ticks wakeDelay = wakeTime-_CurrentTime;
        const Ticks currentWakeDelay = _WakeTime-_CurrentTime;
        if (wakeDelay < currentWakeDelay) {
            _WakeTime = wakeTime;
        }
    }
    
    // Sleep(ticks): sleep current task for `ticks`
    static void Sleep(Ticks ticks) {
        // Disable interrupts while we update globals
        IntState::SetInterruptsEnabled(false);
        
        #warning optimize this function to be smaller
        
        const Ticks wakeTime = _CurrentTime+ticks+1;
        _UpdateWakeTime(wakeTime);
        
        for (;;) {
            IntState::SetInterruptsEnabled(false);
            
            // Wait until some task wakes
            if (!_Wake) {
                _Yield();
                continue;
            }
            
            // Wait until our wake time arrives.
            // If it's not time for this task to wake, this task (and all other sleeping tasks)
            // need to attempt to update _WakeTime, where the soonest wake time wins and
            // determines _WakeTime.
            if (_CurrentTime != wakeTime) {
                _UpdateWakeTime(wakeTime);
                _Yield();
                continue;
            }
            
            _StartWork();
            return;
            
            
//            if (_CurrentTask->sleepCount) {
//                _Yield();
//                continue;
//            }
//            
//            // Update _SleepTask with the task that needs to be woken next
//            Task* sleepTask = nullptr;
//            for (_Task& task : _Tasks) {
//                const Ticks taskSleepCount = task.sleepCount;
//                if (!taskSleepCount) continue; // Ignore tasks that aren't sleeping
//                if (!sleepTask || task.sleepCount<sleepTask->sleepCount) {
//                    sleepTask = &task;
//                }
//            }
//            
//            #warning try this implementation with `sleepTaskSleepCount` to see if it's smaller
////            for (_Task& task : _Tasks) {
////                const Ticks taskSleepCount = task.sleepCount;
////                if (taskSleepCount && taskSleepCount<=sleepTaskSleepCount) {
////                    sleepTask = &task;
////                    sleepTaskSleepCount = taskSleepCount;
////                }
////            }
//            
//            // Subtract the amount of time _CurrentTask was sleeping from the next sleeping task's
//            if (sleepTask) {
//                sleepTask->sleepCount -= sleepTotal;
//            }
//            
//            _SleepTask = sleepTask;
//            _StartWork();
//            return;
        }
        
//         const Ticks taskWakeCounter = ticks + 1;
//         _CurrentTask->wakeCounter = taskWakeCounter;
//         if (!_WakeCounter || (taskWakeCounter < _WakeCounter)) {
//            _WakeCounter = taskWakeCounter;
//         }
//         
//         for (;;) {
//            // Disable interrupts while we check for work.
//            // See explanation in Wait().
//            IntState::SetInterruptsEnabled(false);
//            if (taskWakeTime == _CurrentTime) break;
//            
//            _Yield();
//         }
//         
//         
//         
//         
//         const Ticks taskWakeTime = _CurrentTime + ticks + 1;
//         const Ticks taskWakeDelay = taskWakeTime-_CurrentTime;
//         const Ticks currentWakeDelay = _WakeTime-_CurrentTime;
//         if (taskWakeDelay < currentWakeDelay) {
//            _WakeTime = taskWakeTime;
//         }
//         
//         auto& taskWakeTime = _CurrentTask->wakeTime;
//         taskWakeTime = _CurrentTime + ticks + 1;
//         
//         for (;;) {
//            // Disable interrupts while we check for work.
//            // See explanation in Wait().
//            IntState::SetInterruptsEnabled(false);
//            if (taskWakeTime == _CurrentTime) break;
//            
//            _Yield();
//         }
//         
//         // Update  immediately so that Run() updates `_WakeTime` properly.
//         // This is a cheap hack to minimize the code we emit by keeping the
//         // _WakeTime-updating code in one place (Run())
//         _WakeTimeUpdate = true;
//         
//         _Yield();
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
        
        
        
//        if (!_SleepTask) return false;
//        Ticks& sleepCount = _SleepTask->sleepCount;
//        sleepCount--;
//        return !sleepCount;
        
        
        
//        if (!sleepCount) {
//            return true;
//        }
//        
//        
//        bool wake = false;
//        for (Tick& taskWakeCounter : _WakeCounters) {
//            taskWakeCounter--;
//            wake |= !taskWakeCounter;
//        }
//        return wake;
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
        Ticks sleepTotal = 0;
        Ticks sleepCount = 0;
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
    static inline bool _Wake = false;
    static inline Ticks _WakeTime = 0;
//    static inline _Task* _WakeTask = nullptr;
    
//    static inline Ticks _WakeCounter = 0;
//    static inline Ticks _WakeCounter = 0;
//    static inline bool _Wake = false;
//    static inline bool _WakeTimeUpdate = false;
    
    class Task;
    friend Task;
    
#undef _SPSave
#undef _SPRestore
};

} // namespace Toastbox
