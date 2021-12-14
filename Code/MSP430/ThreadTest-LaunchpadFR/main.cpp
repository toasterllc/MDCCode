#include <msp430.h>
#include <cstddef>
#include <cstdint>
//#include <cstdio>
#include "Task.h"

class TaskA;
class TaskB;
using Scheduler = Toastbox::Scheduler<TaskA,TaskB>;

class TaskA {
public:
    using Options = Scheduler::Options<
        Scheduler::Option::Start // Task should start running
    >;
    
    static void Run() {
        for (;;) {
            PAOUT ^= BIT0;
//            puts("TaskA\n");
            Scheduler::Sleep(10000); // 5.12s
        }
    }
    
    __attribute__((section(".stack.taska")))
    static inline uint8_t Stack[1024];
};

class TaskB {
public:
    using Options = Scheduler::Options<
        Scheduler::Option::Start // Task should start running
    >;
    
    static void Run() {
        for (;;) {
            PAOUT ^= BIT1;
//            puts("TaskB\n");
            Scheduler::Sleep(40000); // 20.48s
        }
    }
    
    __attribute__((section(".stack.taskb")))
    static inline uint8_t Stack[1024];
};

#define _Stringify(s) #s
#define Stringify(s) _Stringify(s)

#define StackMainSize 128
__attribute__((section(".stack.main")))
uint8_t StackMain[StackMainSize];

asm(".global __stack");
asm(".equ __stack, StackMain+" Stringify(StackMainSize));



//// sbrk: custom implementation that accounts for our heap/stack layout.
//// With our custom layout, we know the limit for the heap is `_heap_end`,
//// so abort if we try to expand the heap beyond that.
//extern "C" char* sbrk(int adj) {
//    extern uint8_t _heap_start[];
//    extern uint8_t _heap_end[];
//    
//    static uint8_t* heap = _heap_start;
//    const size_t rem = _heap_end-heap;
//    
//    if (rem < (size_t)adj) {
//        extern void abort();
//        abort();
//    }
//    
//    heap += adj;
//    return (char*)heap;
//}

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

__attribute__((interrupt(WDT_VECTOR)))
static void _ISR_WDT() {
//    PAOUT |= BIT2;
    const bool woke = Scheduler::Tick();
    if (woke) {
        __bic_SR_register_on_exit(GIE | LPM1_bits);
    }
//    PAOUT &= ~BIT2;
}

int main() {
    // Config watchdog timer:
    //   WDTPW:             password
    //   WDTSSEL__SMCLK:    watchdog source = SMCLK
    //   WDTTMSEL:          interval timer mode
    //   WDTCNTCL:          clear counter
    //   WDTIS__8192:       interval = SMCLK / 8192 Hz = 16MHz / 8192 = 1953.125 Hz => period=512 us
    WDTCTL = WDTPW | WDTSSEL__SMCLK | WDTTMSEL | WDTCNTCL | WDTIS__8192;
    SFRIE1 |= WDTIE; // Enable WDT interrupt
    
    PAOUT   = 0x0000;
    PADIR   = BIT2 | BIT1 | BIT0;
    PASEL0  = 0x0000;
    PASEL1  = 0x0000;
    PAREN   = 0x0000;
    PAIE    = 0x0000;
    PAIES   = 0x0000;
    
    // Unlock GPIOs
    PM5CTL0 &= ~LOCKLPM5;
    
    
    
    
    
    // Configure one FRAM wait state if MCLK > 8MHz.
    // This must happen before configuring the clock system.
    FRCTL0 = FRCTLPW | NWAITS_1;
    
//    do {
//        CSCTL7 &= ~(DCOFFG); // Clear DCO fault flag
//        SFRIFG1 &= ~OFIFG;
//    } while (SFRIFG1 & OFIFG); // Test oscillator fault flag
    
    // Disable FLL
    __bis_SR_register(SCG0);
        // Set REFOCLK as FLL reference source
        CSCTL3 |= SELREF__REFOCLK;
        // Clear DCO and MOD registers
        CSCTL0 = 0;
        // Clear DCO frequency select bits first
        CSCTL1 &= ~(DCORSEL_7);
        
        CSCTL1 |= DCORSEL_5;
        
        // Set DCOCLKDIV based on T_MCLKFreqHz and REFOCLK frequency (32768)
        CSCTL2 = FLLD_0 | ((16000000/32768)-1);
        
        // Wait 3 cycles to take effect
        __delay_cycles(3);
    // Enable FLL
    __bic_SR_register(SCG0);
    
    // Wait until FLL locks
    while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
    
    // MCLK / SMCLK source = DCOCLKDIV
    // ACLK source = REFOCLK
    CSCTL4 = SELMS__DCOCLKDIV | SELA__REFOCLK;
    
    
    
    
//    Scheduler::Start<TaskA>();
//    Scheduler::Start<TaskB>();
    
//    // TODO: make tasks have an initial state so we don't need a runtime component to set their initial state
//    Scheduler::Start<TaskA>();
//    Scheduler::Start<TaskB>();
    
    Scheduler::Run();
    return 0;
}

extern "C" [[noreturn]]
void abort() {
    for (;;);
}
