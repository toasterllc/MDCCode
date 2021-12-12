#ifndef __x86_64__
#include <msp430.h>
#endif

#include <cstddef>
#include <cstdint>
#include <stdio.h>

#ifdef __x86_64__

#define _SPSave(dst)
#define _SPRestore(src)

#else

#define _SPSave(dst) asm("mov r1, %0" : "=m" (dst) :           : )
#define _SPRestore(src) asm("mov %0, r1" :            : "m" (src) : )

#endif

static void _start();
static void _yield();
static void _resume();
static void _nop();

using _VoidFn = void(*)();

template <size_t T_StackSize>
class Task {
public:
    void start() {
        _go = _start;
    }
    
    static void Run() {}
    
    _VoidFn _go = _nop;
    void* _sp = _stack + sizeof(_stack);
    uint8_t _stack[T_StackSize];
};

using _Task = Task<0>;

using _TaskRunFn = void(*)(void*);

static _Task* _CurrentTask = nullptr;
static _VoidFn _CurrentTaskRunFn = nullptr;
static void* _SP = nullptr; // Saved stack pointer

static void _start() {
    // Future invocations should execute _resume
    _CurrentTask->_go = _resume;
    
    // Save scheduler's stack pointer
    _SPSave(_SP);
    
    // Restore thread's stack pointer
    _SPRestore(_CurrentTask->_sp);
    
    // Invoke thread's Run()
    _CurrentTaskRunFn();
    
    // The thread finished
    // Future invocations should execute _nop
    _CurrentTask->_go = _nop;
    
    // Restore scheduler stack pointer
    _SPRestore(_SP);
    
    // Return to scheduler
    return;
}

static void _yield() {
    // TODO: do we need to explicitly save registers if _yield/_resume are regular functions?
//    // Push all callee-saved registers (R4-R10)
//    pushm.a #7, r10;
    
    // Save stack pointer
    _SPSave(_CurrentTask->_sp);
    // Restore scheduler's stack pointer
    _SPRestore(_SP);
    // Return to scheduler
    return;
}

static void _resume() {
    // Save scheduler's stack pointer
    _SPSave(_SP);
    // Restore thread's stack pointer
    _SPRestore(_CurrentTask->_sp);
    
    // TODO: do we need to explicitly save registers if _yield/_resume are regular functions?
//    // Pop all callee-saved registers (R4-R10)
//    pop.a #7, r10
    
    // Return to thread, to whatever function called yield()
    return;
}

static void _nop() {
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


void myfun() {
    static volatile int meowmix = 0;
    meowmix++;
}


class SDTask : public Task<1024> {
public:
    static void Run() {
        volatile int i = 0;
        for (;;) {
            i++;
            myfun();
            puts("[SDTask]\n");
            _yield();
        }
    }
};

class ImgTask : public Task<1024> {
public:
    static void Run() {
        volatile int i = 0;
        for (;;) {
            i++;
            myfun();
            puts("[ImgTask]\n");
            _yield();
        }
    }
};

SDTask _sdTask;
ImgTask _imgTask;

int main() {
    _sdTask.start();
    _imgTask.start();
//    for (;;) {
//        puts("[hello]\n");
//    }
    Scheduler::Run(_sdTask, _imgTask);
    return 0;
}
