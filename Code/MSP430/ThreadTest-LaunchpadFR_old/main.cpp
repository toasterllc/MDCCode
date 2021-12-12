#ifndef __x86_64__
#include <msp430.h>
#endif

#include <unistd.h>
#include <stdio.h>
#include <stdint.h>

//call instruction
//    SP -= 2
//    *SP = PC
//    jmp dst

#ifdef __x86_64__

void* SP = nullptr;
#define reta

#endif


static void _start();
static void _yield();
static void _resume();
static void _done();

using _VoidFn = void(*)();

template <size_t T_StackSize>
class Task {
public:
    void start() {
        _go = _start;
    }
    
    static void Run() {}
    
    _VoidFn _go = _done;
    void* _sp = _stack + sizeof(_stack);
    uint8_t _stack[T_StackSize];
};

using _Task = Task<0>;

using _TaskRunFn = void(*)(void*);

static inline _Task* _CurrentTask = nullptr;
static inline _VoidFn _CurrentTaskRunFn = nullptr;
static inline void* _SP = nullptr; // Saved stack pointer

#define _SPGet(dst) asm("mov r1, %0" : "=m" (dst) :           : )
#define _SPSet(src) asm("mov %0, r1" :            : "m" (src) : )

static void _start() {
    // Future invocations should execute _resume
    _CurrentTask->_go = _resume;
    
    // Save scheduler's stack pointer
    _SPGet(_SP);
    
    // Restore thread's stack pointer
    _SPSet(_CurrentTask->_sp);
    
    // Invoke thread's Run()
    _CurrentTaskRunFn();
    
    // The thread finished
    // Future invocations should execute _done
    _CurrentTask->_go = _done;
    
    // Restore scheduler stack pointer
    _SPSet(_SP);
    
    // Return to scheduler
    return;
}

static void _yield() {
    // TODO: do we need to explicitly save registers if _yield/_resume are regular functions?
//    // Push all callee-saved registers (R4-R10)
//    pushm.a #7, r10;
    
    // Save stack pointer
    _SPGet(_CurrentTask->_sp);
    // Restore scheduler's stack pointer
    _SPSet(_SP);
    // Return to scheduler
    return;
}

static void _resume() {
    // Save scheduler's stack pointer
    _SPGet(_SP);
    // Restore thread's stack pointer
    _SPSet(_CurrentTask->_sp);
    
    // TODO: do we need to explicitly save registers if _yield/_resume are regular functions?
//    // Pop all callee-saved registers (R4-R10)
//    pop.a #7, r10
    
    // Return to thread, to whatever function called yield()
    return;
}

static void _done() {
    // Return to scheduler
    return;
}

class Scheduler {
public:
    template <typename T_Task, typename... T_Tasks>
    static void _Run(T_Task& task, T_Tasks&... tasks) {
        _CurrentTaskRunFn = T_Task::Run;
        _CurrentTask = &reinterpret_cast<_Task&>(task);
        _CurrentTask->_go();
        if constexpr (sizeof...(tasks)) _Run(tasks...);
    }
    
    template <typename... T_Tasks>
    static void Run(T_Tasks&... tasks) {
        for (;;) {
            _Run(tasks...);
        }
    }
    
protected:
    
    
    bool _didWork = false;
};



class SDTask : public Task<128> {
public:
    static void Run() {
        volatile int i = 0;
        for (;;) {
            i++;
            
#ifdef __x86_64__
            printf("[SDTask] %d\n", i);
#endif
            
            _yield();
        }
    }
};

class ImgTask : public Task<128> {
public:
    static void Run() {
        volatile int i = 0;
        for (;;) {
            i++;
            
#ifdef __x86_64__
            printf("[ImgTask] %d\n", i);
#endif
            
            _yield();
        }
    }
};

SDTask _sdTask;
ImgTask _imgTask;

int main() {
    _sdTask.start();
    _imgTask.start();
    
//    printf("%p\n", _sdTask._run);
//    printf("%p\n", _imgTask._run);
//    
//    printf("%p\n", &SDTask::run);
//    printf("%p\n", &ImgTask::run);
    
    Scheduler::Run(_sdTask, _imgTask);
    return 0;
}
