#include <msp430.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include "GPIO.h"
#include "Clock.h"
#include "Assert.h"

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
//    using ICE_MSP_SPI_DATA_UCA0SOMI         = GPIOA<0x5, GPIOOption::Output0>;
    using ICE_MSP_SPI_DATA_UCA0SOMI         = GPIOA<0x5, GPIOOption::Input, GPIOOption::Resistor0>;
    using ICE_MSP_SPI_CLK_MANUAL            = GPIOA<0x6, GPIOOption::Output1>;
    using ICE_MSP_SPI_AUX                   = GPIOA<0x7, GPIOOption::Output0>;
    using XOUT                              = GPIOA<0x8, GPIOOption::Sel10>;
    using XIN                               = GPIOA<0x9, GPIOOption::Sel10>;
    using ICE_MSP_SPI_AUX_DIR               = GPIOA<0xA, GPIOOption::Output1>;
    using VDD_SD_EN                         = GPIOA<0xB, GPIOOption::Output0>;
    using VDD_B_EN_                         = GPIOA<0xC, GPIOOption::Output1>;
    using MOTION_SIGNAL                     = GPIOA<0xD, GPIOOption::Input>;
    
    using DEBUG_OUT                         = GPIOA<0xE, GPIOOption::Output0>;
};

using Clock = ClockType<XT1FreqHz, MCLKFreqHz>;

#pragma mark - Interrupts

static volatile bool Event = false;

__attribute__((interrupt(PORT1_VECTOR)))
void _isr_port1() {
    
    // Cold start
    for (int i=0;; i++) {
        Pin::DEBUG_OUT::Write(i&1);
    }
    
    // Accessing `P1IV` automatically clears the highest-priority interrupt
    switch (__even_in_range(P1IV, P1IV__P1IFG7)) {
    case P1IV__P1IFG4:
        Event = true;
        __bic_SR_register_on_exit(LPM3_bits);
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
    
    SYSCFG0 = FRWPPW; // Enable FRAM writes
    
//    P1IFG = 0;
//    P2IFG = 0;
    
    if (SYSRSTIV == SYSRSTIV_LPM5WU) {
        // Wake from LPM3.5
        for (int i=0; i<1000; i++) {
            _sleepMs(5);
            Pin::DEBUG_OUT::Write(i&1);
        }
    
    } else {
        // Cold start
        for (int i=0; i<500; i++) {
            _sleepMs(10);
            Pin::DEBUG_OUT::Write(i&1);
        }
        
        P1IFG = 0;
    }
    
    __bis_SR_register(GIE);
    
//    bool first = true;
    for (;;) {
        // Disable ints while we check for events
        __bic_SR_register(GIE);
        
        if (!Event) {
//            if (first) {
//                // We don't have an event, so this should be a cold start (ie we
//                // didn't wake up from LPM3.5)
//                Assert(SYSRSTIV != SYSRSTIV_LPM5WU);
//                first = false;
//            }
            
//            P1IFG |= (1<<4);
            
//            // Artificially trigger an interrupt
//            Pin::ICE_MSP_SPI_DATA_UCA0SOMI::Write(1);
//            Pin::ICE_MSP_SPI_DATA_UCA0SOMI::Write(0);
            
//            // Disable regulator so we enter LPM3.5 (instead of just LPM3)
//            PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
//            PMMCTL0_L |= PMMREGOFF;
            
            // Go to sleep in LPM3.5
            __bis_SR_register(GIE | LPM3_bits);
        }
        
//        if (first) {
//            // We do have an event, so we should have woken up from LPM3.5
//            Assert(SYSRSTIV == SYSRSTIV_LPM5WU);
//            first = false;
//        }
        
        // Clear event flag
        Event = false;
        // Re-enable interrupts while we handle the event
        __bis_SR_register(GIE);
        
//        Pin::DEBUG_OUT::Write(Debug);
        
//        do {
//            // Disable ints while we check for events
//            __bic_SR_register(GIE);
//            
//            if (!Event)
//            
//            // Check for events
//            if (Event) {
//                // Enable ints while we handle the event
//                __bis_SR_register(GIE);
//                
//                Pin::DEBUG_OUT::Write(Debug);
//                Debug = !Debug;
//                Event = false;
//            }
//            
//            // Enable ints while we check for events
//            __bis_SR_register(GIE);
//        }
//        
//        _sleepMs(50);
////        __bic_SR_register(GIE);
//        
//        P1IFG |= (1<<4);
//        
//        
//        // Disable regulator so we enter LPM3.5 (instead of just LPM3)
//        PMMCTL0_H = PMMPW_H; // Open PMM Registers for write
//        PMMCTL0_L |= PMMREGOFF;
//        
//        // Go to sleep in LPM3.5
//        __bis_SR_register(GIE | LPM3_bits);
    }
    
    return 0;
}
