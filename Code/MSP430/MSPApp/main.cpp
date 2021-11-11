#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include "GPIO.h"
#include "Clock.h"

static constexpr uint64_t MCLKFreqHz = 16000000;
static constexpr uint32_t XT1FreqHz = 32768;

#define _sleepUs(us) __delay_cycles((((uint64_t)us)*MCLKFreqHz) / 1000000)
#define _sleepMs(ms) __delay_cycles((((uint64_t)ms)*MCLKFreqHz) / 1000)

struct Pin {
    // Default GPIOs
    using VDD_1V9_IMG_EN                    = GPIOA<0x0, GPIOOption::Output0>;
    using VDD_2V8_IMG_EN                    = GPIOA<0x2, GPIOOption::Output0>;
    using ICE_MSP_SPI_DATA_DIR              = GPIOA<0x3, GPIOOption::Output1>;
    using ICE_MSP_SPI_DATA_IN               = GPIOA<0x4, GPIOOption::Interrupt01>;
    using ICE_MSP_SPI_DATA_UCA0SOMI         = GPIOA<0x5, GPIOOption::Sel01>;
    using ICE_MSP_SPI_CLK_MANUAL            = GPIOA<0x6, GPIOOption::Output1>;
    using ICE_MSP_SPI_AUX                   = GPIOA<0x7, GPIOOption::Output0>;
    using XOUT                              = GPIOA<0x8, GPIOOption::Sel10>;
    using XIN                               = GPIOA<0x9, GPIOOption::Sel10>;
    using ICE_MSP_SPI_AUX_DIR               = GPIOA<0xA, GPIOOption::Output1>;
    using VDD_SD_EN                         = GPIOA<0xB, GPIOOption::Output0>;
    using VDD_B_EN_                         = GPIOA<0xC, GPIOOption::Output1>;
    using MOTION_SIGNAL                     = GPIOA<0xD, GPIOOption::Input>;
//    using MOTION_SIGNAL                     = GPIOA<0xD, GPIOOption::Interrupt01>;
    
    using DEBUG_OUT                         = GPIOA<0xE, GPIOOption::Output0>;
    
    // Alternate versions of above GPIOs
    using ICE_MSP_SPI_DATA_UCA0SIMO         = GPIOA<0x4, GPIOOption::Sel01>;
    using ICE_MSP_SPI_CLK_UCA0CLK           = GPIOA<0x6, GPIOOption::Sel01>;
};

using Clock = ClockType<XT1FreqHz, MCLKFreqHz>;

#pragma mark - Interrupts

__interrupt
__attribute__((interrupt(PORT1_VECTOR)))
void _isr_port1() {
    __attribute__((section(".persistent")))
    static bool debug = 0;
    
    // Accessing `P1IV` automatically clears the highest-priority interrupt
    switch (__even_in_range(P1IV, P1IV__P1IFG7)) {
    case P1IV__P1IFG4:
        Pin::DEBUG_OUT::Write(debug);
        
        SYSCFG0 = FRWPPW; // Enable FRAM writes
        debug = !debug;
        
        __bic_SR_register_on_exit(LPM1_bits);
        break;
    default:
        break;
    }
}

#pragma mark - Main

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Init GPIOs
    GPIOInit<
        Pin::VDD_1V9_IMG_EN,
        Pin::VDD_2V8_IMG_EN,
        Pin::ICE_MSP_SPI_DATA_DIR,
        Pin::ICE_MSP_SPI_DATA_IN,
        Pin::ICE_MSP_SPI_DATA_UCA0SOMI,
        Pin::ICE_MSP_SPI_CLK_MANUAL,
        Pin::ICE_MSP_SPI_AUX,
        Pin::XOUT,
        Pin::XIN,
        Pin::ICE_MSP_SPI_AUX_DIR,
        Pin::VDD_SD_EN,
        Pin::VDD_B_EN_,
        Pin::MOTION_SIGNAL,
        Pin::DEBUG_OUT
    >();
    
    // Init clock
    Clock::Init();
    
//    P1IFG = 0;
//    P2IFG = 0;
//    
//    __bis_SR_register(GIE);
    
    for (;;) {
//        _sleepMs(50);
//        __bic_SR_register(GIE);
        
        P1IFG |= (1<<4);
        
//        // Disable regulator so we enter LPM3.5 (instead of just LPM3)
//        PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
//        PMMCTL0_L |= PMMREGOFF;
        
        // Go to sleep in LPM3.5
        __bis_SR_register(GIE | LPM1_bits);
    }
    
    
//    __bis_SR_register(GIE);
    
//    P1IFG |= (1<<4);
//    
//    for (;;);
    
    // Enable interrupts
//    __bis_SR_register(GIE);
    
//    Pin::DEBUG_OUT::Write(1);
//    P1IFG |= 0xFF;
//    for (;;);
    
//    _sleepMs(1);
    
//    for (;;) {
////        _sleepMs(50);
////        __bic_SR_register(GIE);
//        
//        P1IFG |= (1<<4);
//        for (;;);
//        
////        // Disable regulator so we enter LPM3.5 (instead of just LPM3)
////        PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
////        PMMCTL0_L |= PMMREGOFF;
//        
//        // Go to sleep in LPM3.5
//        __bis_SR_register(GIE | LPM3_bits);
//    }
    
    return 0;
}
