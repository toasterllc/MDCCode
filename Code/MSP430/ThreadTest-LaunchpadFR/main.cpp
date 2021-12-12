#include <msp430.h>
#include <cstddef>
#include <cstdint>
#include <stdio.h>
#include "Task.h"
using namespace Toastbox;

class SDTask : public Task<SDTask> {
public:
    static void Run() {
        volatile int i = 0;
        for (;;) {
            i++;
            puts("[SDTask]\n");
            Scheduler::Yield();
        }
    }
    
    __attribute__((section(".stack.sdtask")))
    static inline uint8_t Stack[1024];
};

class ImgTask : public Task<ImgTask> {
public:
    static void Run() {
        volatile int i = 0;
        for (;;) {
            i++;
            puts("[ImgTask]\n");
            Scheduler::Yield();
        }
    }
    
    __attribute__((section(".stack.imgtask")))
    static inline uint8_t Stack[1024];
};

#define _Stringify(s) #s
#define Stringify(s) _Stringify(s)

#define StackMainSize 128
__attribute__((section(".stack.main")))
uint8_t StackMain[StackMainSize];

asm(".global __stack");
asm(".equ __stack, StackMain+" Stringify(StackMainSize));



// sbrk: custom implementation that accounts for our heap/stack layout.
// With our custom layout, we know the limit for the heap is `_heap_end`,
// so abort if we try to expand the heap beyond that.
extern "C" char* sbrk(int adj) {
    extern uint8_t _heap_start[];
    extern uint8_t _heap_end[];
    
    static uint8_t* heap = _heap_start;
    const size_t rem = _heap_end-heap;
    
    if (rem < (size_t)adj) {
        extern void abort();
        abort();
    }
    
    heap += adj;
    return (char*)heap;
}


int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // TODO: make tasks have an initial state so we don't need a runtime component to set their initial state
    SDTask::Start();
    ImgTask::Start();
    
    Scheduler::Run<SDTask, ImgTask>();
    return 0;
}
