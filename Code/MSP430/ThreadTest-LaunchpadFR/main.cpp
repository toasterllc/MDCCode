#include <msp430.h>
#include <cstddef>
#include <cstdint>
//#include <stdio.h>
#include "Task.h"
using namespace Toastbox;

struct {
    volatile int i = 0;
} _sd;

struct {
    volatile int i = 0;
} _img;


class SDTask : public Task<SDTask> {
public:
    static void Run() {
        for (;;) {
//            puts("[SDTask]\n");
            _sd.i++;
            Scheduler::Yield();
        }
    }
    
    __attribute__((section(".stack.sdtask")))
    static inline uint8_t Stack[1024];
};

class ImgTask : public Task<ImgTask> {
public:
    static void Run() {
        for (;;) {
            Scheduler::Wait([&] { return !(_sd.i % 0x4); });
            _img.i++;
//            puts("[ImgTask]\n");
            // Force a yield, otherwise our Wait() expression will never return false and we'll never yield
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

// MARK: - IntState

inline bool Toastbox::IntState::InterruptsEnabled() {
    return __get_SR_register() & GIE;
}

inline void Toastbox::IntState::SetInterruptsEnabled(bool en) {
    if (en) __bis_SR_register(GIE);
    else    __bic_SR_register(GIE);
}

void Toastbox::IntState::WaitForInterrupt() {
    const bool prevEn = Toastbox::IntState::InterruptsEnabled();
    __bis_SR_register(GIE | LPM1_bits);
    if (!prevEn) Toastbox::IntState::SetInterruptsEnabled(false);
}

extern "C"
[[noreturn]]
void abort() {
    for (;;);
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
