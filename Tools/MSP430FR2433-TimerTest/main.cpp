#include <msp430.h>
#include "GPIO.h"
#include "Assert.h"
#include "Toastbox/Util.h"
using namespace GPIO;

struct _Pin {
    using LED1      = PortA::Pin<0x0, Option::Output0>;
    using INT       = PortA::Pin<0x1, Option::Interrupt10>; // P1.1
    using MCLK      = PortA::Pin<0x3, Option::Output0, Option::Sel10>; // P1.3 (MCLK)
};

// Abort(): called by Assert() with the address that aborted
extern "C"
[[noreturn, gnu::used]]
void Abort(uintptr_t addr) {
    for (;;);
}

// MARK: - _TaskMain

#define _TaskMainStackSize 128

SchedulerStack(".stack._TaskMain")
uint8_t _TaskMainStack[_TaskMainStackSize];

asm(".global _StartupStack");
asm(".equ _StartupStack, _TaskMainStack+" Stringify(_TaskMainStackSize));

static void ClockInit16MHz() {
    constexpr uint32_t T_MCLKFreqHz = 16000000;
    constexpr uint32_t REFOCLKFreqHz = 32768;
    const uint16_t* CSCTL0Cal16MHz = (uint16_t*)0x1A22;
    
    // Configure one FRAM wait state if MCLK > 8MHz.
    // This must happen before configuring the clock system.
    if constexpr (T_MCLKFreqHz > 8000000) {
        FRCTL0 = FRCTLPW | NWAITS_1;
    }
    
    // Disable FLL
    __bis_SR_register(SCG0);
        // Set REFO as FLL reference source
        CSCTL3 |= SELREF__REFOCLK;
        // Clear DCO and MOD registers
        CSCTL0 = 0;
        // Clear DCO frequency select bits first
        CSCTL1 &= ~(DCORSEL_7);
        
        if constexpr (T_MCLKFreqHz == 16000000) {
            CSCTL1 |= DCORSEL_5;
        } else if constexpr (T_MCLKFreqHz == 12000000) {
            CSCTL1 |= DCORSEL_4;
        } else if constexpr (T_MCLKFreqHz == 8000000) {
            CSCTL1 |= DCORSEL_3;
        } else if constexpr (T_MCLKFreqHz == 4000000) {
            CSCTL1 |= DCORSEL_2;
        } else if constexpr (T_MCLKFreqHz == 2000000) {
            CSCTL1 |= DCORSEL_1;
        } else if constexpr (T_MCLKFreqHz == 1000000) {
            CSCTL1 |= DCORSEL_0;
        }
        
        // Set DCOCLKDIV based on T_MCLKFreqHz and REFOCLKFreqHz
        CSCTL2 = FLLD_0 | ((T_MCLKFreqHz/REFOCLKFreqHz)-1);
        
        // Special case: use the factory-calibrated values for CSCTL0 if one is available for the target frequency
        // This significantly speeds up the FLL lock time; without this technique, it takes ~200ms to get an FLL
        // lock (datasheet specifies 280ms as typical). Using the factory-calibrated value, an FLL lock takes 800us.
        if constexpr (T_MCLKFreqHz == 16000000) {
            CSCTL0 = *CSCTL0Cal16MHz;
        }
        
        // Wait 3 cycles to take effect
        __delay_cycles(3);
    // Enable FLL
    __bic_SR_register(SCG0);
    
    // Special case: if we're using one of the factory-calibrated values for CSCTL0 (see above),
    // we need to delay 10 REFOCLK cycles. We do this by temporarily switching MCLK to be sourced
    // by REFOCLK, and waiting 10 cycles.
    // This technique is prescribed by "MSP430FR2xx/FR4xx DCO+FLL Applications Guide", and shown
    // by the "MSP430FR2x5x_FLL_FastLock_24MHz-16MHz.c" example code.
    if constexpr (T_MCLKFreqHz == 16000000) {
        CSCTL4 = SELMS__REFOCLK | SELA__REFOCLK;
        __delay_cycles(10);
    }
    
    // Wait until FLL locks
    while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
    
    // MCLK=DCOCLK, ACLK=XT1
    CSCTL4 = SELMS__DCOCLKDIV | SELA__REFOCLK;
}

[[gnu::interrupt]]
void _ISR_PORT1() {
    static uint16_t counter = 0;
    switch (P1IV) {
    case _Pin::INT::IVPort1():
        counter++;
        if (counter == 20000) {
            counter = 0;
            _Pin::LED1::Write(!_Pin::LED1::Read());
        }
        break;
    default:
        Assert(false);
    }
}

[[gnu::interrupt]]
void _ISR_TIMER0_A1() {
    switch (TA0IV) {
    case TA0IV_TAIFG:
        static uint16_t counter = 0;
        counter++;
        if (counter == 5000) {
            counter = 0;
            _Pin::LED1::Write(!_Pin::LED1::Read());
        }
        break;
    default:
        Assert(false);
    }
}

inline bool Toastbox::IntState::Get() {
    return __get_SR_register() & GIE;
}

inline void Toastbox::IntState::Set(bool en) {
    if (en) __bis_SR_register(GIE);
    else    __bic_SR_register(GIE);
}

int main() {
    WDTCTL = WDTPW | WDTHOLD;
    
    ClockInit16MHz();
    
    GPIO::Init<
        _Pin::LED1,
        _Pin::INT,
        _Pin::MCLK
    >();
    
    TA0EX0 = 0;
    TA0CCR0 = 2;
    TA0CTL =
        TASSEL__ACLK    |   // clock source = ACLK
        ID__1           |   // clock divider = /8
        MC__UPDOWN      |   // mode = up
        TACLR           |   // reset timer state
        TAIE            ;   // enable interrupt
    
    __bis_SR_register(GIE | LPM3_bits);
    // Catch ourself if we ever exit sleep
    Toastbox::IntState::Set(false);
    for (;;);
}
