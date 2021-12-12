#pragma once

namespace Toastbox {

struct _TaskState {
    using VoidFn = void(*)();
    
    const VoidFn run;
    void* sp;
    VoidFn go;
    
    static inline _TaskState* Current = nullptr; // Current task's _TaskState
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
    template <typename... T_Tasks>
    static void Run() {
        for (;;) {
            _Run<T_Tasks...>();
        }
    }
    
    [[gnu::noinline]] // Disable inlining because PC must be pushed onto the stack when called
    static void Yield() {
        // Save stack pointer
        _SPSave(_TaskState::Current->sp);
        // Restore scheduler's stack pointer
        _SPRestore(_TaskState::SP);
        // Return to scheduler
        return;
    }
    
private:
    template <typename T_Task, typename... T_Tasks>
    static void _Run() {
        _TaskState::Current = &T_Task::_State;
        _TaskState::Current->go();
        if constexpr (sizeof...(T_Tasks)) _Run<T_Tasks...>();
    }
    
    [[gnu::noinline]] // Disable inlining because PC must be pushed onto the stack when called
    static void _Start() {
        // Future invocations should execute _Resume
        _TaskState::Current->go = _Resume;
        
        // Save scheduler's stack pointer
        _SPSave(_TaskState::SP);
        // Restore task's stack pointer
        _SPRestore(_TaskState::Current->sp);
        
        // Invoke task's Run()
        _TaskState::Current->run();
        // The task finished
        // Future invocations should execute _nop
        _TaskState::Current->go = _Nop;
        
        // Restore scheduler stack pointer
        _SPRestore(_TaskState::SP);
        // Return to scheduler
        return;
    }
    
    [[gnu::noinline]] // Disable inlining because PC must be pushed onto the stack when called
    static void _Resume() {
        // Save scheduler's stack pointer
        _SPSave(_TaskState::SP);
        // Restore task's stack pointer
        _SPRestore(_TaskState::Current->sp);
        // Return to task, to whatever function called Yield()
        return;
    }
    
    [[gnu::noinline]] // Disable inlining because PC must be pushed onto the stack when called
    static void _Nop() {
        // Return to scheduler
        return;
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
        _State.go = Scheduler::_Start;
    }
    
private:
    static inline _TaskState _State = {
        .run = T_Subclass::Run,
        .sp = T_Subclass::Stack + sizeof(T_Subclass::Stack),
        .go = Scheduler::_Nop,
    };
    
    friend Scheduler;
};

} // namespace Toastbox
