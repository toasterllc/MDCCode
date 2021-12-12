#define _SPSave(dst)                                                                \
         if constexpr (sizeof(void*) == 2)  asm("mov  r1, %0" : "=m" (dst) : : );   \
    else if constexpr (sizeof(void*) == 4)  asm("mova r1, %0" : "=m" (dst) : : )

#define _SPRestore(src)                                                             \
         if constexpr (sizeof(void*) == 2)  asm("mov  %0, r1" : : "m" (src) : );    \
    else if constexpr (sizeof(void*) == 4)  asm("mova %0, r1" : : "m" (src) : )

static void _Resume();
static void _Nop();

using _VoidFn = void(*)();

struct _TaskState {
    const _VoidFn run;
    void* sp;
    _VoidFn go;
};

static _TaskState* _CurrentTaskState = nullptr;
static void* _SP = nullptr; // Saved stack pointer

[[gnu::noinline]]
static void _Start() {
    // Future invocations should execute _Resume
    _CurrentTaskState->go = _Resume;
    
    // Save scheduler's stack pointer
    _SPSave(_SP);
    // Restore thread's stack pointer
    _SPRestore(_CurrentTaskState->sp);
    
    // Invoke thread's Run()
    _CurrentTaskState->run();
    // The thread finished
    // Future invocations should execute _nop
    _CurrentTaskState->go = _Nop;
    
    // Restore scheduler stack pointer
    _SPRestore(_SP);
    // Return to scheduler
    return;
}

[[gnu::noinline]]
static void _Yield() {
    // Save stack pointer
    _SPSave(_CurrentTaskState->sp);
    // Restore scheduler's stack pointer
    _SPRestore(_SP);
    // Return to scheduler
    return;
}

[[gnu::noinline]]
static void _Resume() {
    // Save scheduler's stack pointer
    _SPSave(_SP);
    // Restore thread's stack pointer
    _SPRestore(_CurrentTaskState->sp);
    // Return to thread, to whatever function called _Yield()
    return;
}

[[gnu::noinline]]
static void _Nop() {
    // Return to scheduler
    return;
}

template <typename T_Subclass>
class Task {
public:
    static void Start() {
        _State.go = _Start;
    }
    
    static inline _TaskState _State = {
        .run = T_Subclass::Run,
        .sp = T_Subclass::Stack + sizeof(T_Subclass::Stack),
        .go = _Nop,
    };
};

class Scheduler {
public:
    template <typename T_Task, typename... T_Tasks>
    static void _Run() {
        _CurrentTaskState = &T_Task::_State;
        _CurrentTaskState->go();
        if constexpr (sizeof...(T_Tasks)) _Run<T_Tasks...>();
    }
    
    template <typename... T_Tasks>
    static void Run() {
        for (;;) {
            _Run<T_Tasks...>();
        }
    }
};
