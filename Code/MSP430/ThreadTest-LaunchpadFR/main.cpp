#include <msp430.h>
#include <cstddef>
#include <cstdint>
#include <stdio.h>
#include "Task.h"

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

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // TODO: make tasks have an initial state so we don't need a runtime component to set their initial state
    SDTask::Start();
    ImgTask::Start();
    
    Scheduler::Run<SDTask, ImgTask>();
    return 0;
}
