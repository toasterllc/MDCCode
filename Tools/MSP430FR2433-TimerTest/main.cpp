#include <msp430.h>
#include "GPIO.h"
#include "Assert.h"
#include "Toastbox/Util.h"
using namespace GPIO;

struct _Pin {
    using LED1      = PortA::Pin<0x0, Option::Output0>;
    using LED2      = PortA::Pin<0x1, Option::Output0>;
    using BUTTON2   = PortA::Pin<0xF, Option::Resistor1, Option::Interrupt10>;
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

//[[gnu::interrupt]]
//void _ISR_PORT2() {
//    // Accessing `P2IV` automatically clears the highest-priority interrupt
//    const uint16_t iv = P2IV;
//    _Pin::LED1::Write(_Pin::LED1::Read());
//}

[[gnu::interrupt]]
void _ISR_PORT2() {
    const uint16_t iv = P2IV;
    switch (__even_in_range(iv, _Pin::IVPort2())) {
    case _Pin::BUTTON2::IVPort2():
        __bic_SR_register_on_exit(LPM3_bits);
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
    ClockInit16MHz();
    
    // Init GPIOs
    GPIO::Init<
        // LEDs
        _Pin::LED1,
        _Pin::LED2,
        _Pin::BUTTON2
    >();
    
    uint16_t counter = 0;
    for (;;) {
        __bis_SR_register(GIE | LPM3_bits);
        
        counter++;
        if (counter == 8) {
            counter = 0;
            _Pin::LED1::Write(!_Pin::LED1::Read());
        }
    }
    
//    for (;;) {
//        _Pin::LED1::Write(1);
//        __delay_cycles(1000000);
//        _Pin::LED1::Write(0);
//        __delay_cycles(1000000);
//    }
}
