#include <msp430.h>
#include <cstddef>
#include <cstdint>
#include <stdio.h>

#include "Task.h"


__attribute__((section(".meow")))
uint8_t MyVal[128] __attribute__((used));

class SDTask : public Task<SDTask, 1024> {
public:
    static void Run() {
        MyVal[0] = 0;
        volatile int i = 0;
        for (;;) {
            i++;
            puts("[SDTask]\n");
            _Yield();
        }
    }
};

class ImgTask : public Task<ImgTask, 1024> {
public:
    static void Run() {
        volatile int i = 0;
        for (;;) {
            i++;
            puts("[ImgTask]\n");
            _Yield();
        }
    }
};

//template <typename T_Subclass, size_t T_StackSize>
//uint8_t Task<T_Subclass, T_StackSize>::_Stack[T_StackSize];

//// Prevent system from thinking we've overflowed the stack
//// TODO: how do we fix this for real? look at actual sbrk() code in newlib. 
//// move stacks into .stack region?
//// look at current task sp and compare to _sbrk_heap?
//extern "C" char* sbrk(int) {
//    extern char* _sbrk_heap;
//    return _sbrk_heap;
//}

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // TODO: make tasks have an initial state so we don't need a runtime component to set their initial state
    SDTask::Start();
    ImgTask::Start();
    
    Scheduler::Run<SDTask, ImgTask>();
    return 0;
}
