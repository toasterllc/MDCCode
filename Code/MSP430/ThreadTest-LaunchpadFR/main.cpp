#include <msp430.h>
#include <cstddef>
#include <cstdint>
//#include <cstdio>
#define TaskMSP430
#include "Toastbox/Task.h"
#include "Toastbox/IntState.h"
#include "Util.h"
#include "Scheduler.h"

#define StackMainSize 128

[[gnu::section(".stack.main"), gnu::used]]
uint8_t StackMain[StackMainSize];

asm(".global __stack");
asm(".equ __stack, StackMain+" Stringify(StackMainSize));

static bool Flag = false;

class TaskA {
public:
    static void Run() {
        for (;;) {
//            PAOUT ^= BIT0;
            
//            Scheduler::Start<TaskA,MyFun>();
//            Scheduler::Start<TaskA>(MyFun);
//            Scheduler::Start<TaskB>(MyFun);
//            Scheduler::Wait<TaskB>();
            
//            puts("TaskA\n");
//            Scheduler::Sleep(10000); // 5.12s
            
            Scheduler::Sleep(Scheduler::Ms(2000));
            Flag = true;
//            Flag = !Flag;
        }
    }
    
    __attribute__((section(".stack.TaskA")))
    static inline uint8_t Stack[1024];
    
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run,
    };
};

class TaskB {
public:
    static void Run() {
        for (;;) {
//            PAOUT ^= BIT1;
//            puts("TaskB\n");
//            auto ok = Scheduler::Sleep(Scheduler::Ms(1000));
            const auto ok = Scheduler::Wait(Scheduler::Ms(100), [] { return Flag; });
            
            if (ok) {
                Flag = false;
                PAOUT ^= BIT0;
            } else {
                PAOUT ^= BIT1;
            }
        }
    }
    
    __attribute__((section(".stack.TaskB")))
    static inline uint8_t Stack[1024];
    
    static constexpr Toastbox::TaskOptions Options{
        .AutoStart = Run,
    };
};

// MARK: - IntState

inline bool Toastbox::IntState::InterruptsEnabled() {
    return __get_SR_register() & GIE;
}

inline void Toastbox::IntState::SetInterruptsEnabled(bool en) {
    if (en) __bis_SR_register(GIE);
    else    __bic_SR_register(GIE);
}

void _Sleep() {
    __bis_SR_register(GIE | LPM1_bits);
}

void _Error(uint16_t) {
    abort();
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

template <typename... T_Tasks>
static void _resetTasks() {
    (Scheduler::Stop<T_Tasks>(), ...);
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
    
    {
        // Configure one FRAM wait state if MCLK > 8MHz.
        // This must happen before configuring the clock system.
        FRCTL0 = FRCTLPW | NWAITS_1;
        
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
    }
    
//    using Meow = Scheduler::Options<
//        Scheduler::Option::AutoStart<_ISR_WDT>
//    >;
//    
//    Meow::AutoStart::Fn;
    
//    {
//        using Opts = Scheduler::Options<
//            Scheduler::Option::AutoStart<_ISR_WDT>
//        >;
//        VoidFn fn = Opts::AutoStart::Fn;
//        fn();
//    }
    
//    {
//        using Opts = Options<Option::AutoStart<_ISR_WDT>>;
//        VoidFn fn = Opts::AutoStart::Fn;
//        fn();
//    }
    
//    #define Subtasks TaskA, TaskB
//    _resetTasks<Subtasks>();
    
//    Scheduler::Stop<Subtasks...>();
    
//    (std::is_same_v<T, Forbidden> && ...);
    
    
    
    
    Scheduler::Run();
    return 0;
}

extern "C" [[noreturn]]
void abort() {
    for (;;);
}
