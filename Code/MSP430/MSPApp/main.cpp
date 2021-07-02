#include <msp430fr2422.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>
#include <cstddef>
#include "ICE40.h"

static void _clockInit() {
    constexpr uint32_t MCLKFreqHz = 16000000;
    constexpr uint32_t XT1FreqHz = 32768;
    
    // Configure one FRAM wait state, as required by the device datasheet for MCLK > 8MHz.
    // This must happen before configuring the clock system.
    FRCTL0 = FRCTLPW | NWAITS_1;
    
    // Make PA.8 and PA.9 XOUT/XIN
    PASEL1 |=  (BIT8 | BIT9);
    PASEL0 &= ~(BIT8 | BIT9);
    
    do {
        CSCTL7 &= ~(XT1OFFG | DCOFFG); // Clear XT1 and DCO fault flag
        SFRIFG1 &= ~OFIFG;
    } while (SFRIFG1 & OFIFG); // Test oscillator fault flag
    
    // Disable FLL
    __bis_SR_register(SCG0);
        // Set XT1 as FLL reference source
        CSCTL3 |= SELREF__XT1CLK;
        // Clear DCO and MOD registers
        CSCTL0 = 0;
        // Clear DCO frequency select bits first
        CSCTL1 &= ~(DCORSEL_7);
        // Set DCO = 16MHz
        CSCTL1 |= DCORSEL_5;
        // DCOCLKDIV = 16MHz
        CSCTL2 = FLLD_0 | ((MCLKFreqHz/XT1FreqHz)-1);
        // Wait 3 cycles to take effect
        __delay_cycles(3);
    // Enable FLL
    __bic_SR_register(SCG0);
    
    // Wait until FLL locks
    while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
    
    // MCLK / SMCLK source = DCOCLKDIV
    // ACLK source = XT1
    CSCTL4 = SELMS__DCOCLKDIV | SELA__XT1CLK;
}

static void _sysInit() {
    // Stop watchdog timer
    {
        WDTCTL = WDTPW | WDTHOLD;
    }
    
    // Reset pin states
    {
        PAOUT   = 0x0000;
        PADIR   = 0x0000;
        PASEL0  = 0x0000;
        PASEL1  = 0x0000;
        PAREN   = 0x0000;
    }
    
    // Configure clock system
    {
        _clockInit();
    }
    
    // Unlock GPIOs
    {
        PM5CTL0 &= ~LOCKLPM5;
    }
}

// uint8_t RXData = 0;
// uint8_t TXData = 0;
//
// __interrupt __attribute__((interrupt(USCI_A0_VECTOR)))
// static void _isrUSCIA0() {
//     switch (UCA0IV) {
//     case USCI_SPI_UCRXIFG:
//         RXData = UCA0RXBUF;
//         UCA0IFG &= ~UCRXIFG;
//         // Wake up to setup next TX
//         __bic_SR_register_on_exit(LPM0_bits);
//         break;
//
//     case USCI_SPI_UCTXIFG:
//         UCA0TXBUF = TXData;
//         UCA0IE &= ~UCTXIE;
//         break;
//
//     default:
//         break;
//     }
// }



// static void tx(uint8_t b) {
//     // Clear UCRXIFG so we can tell when tx/rx is complete
//     UCA0IFG &= ~UCRXIFG;
//     // Wait until `UCA0TXBUF` can accept more data
//     while (!(UCA0IV & UCTXIFG));
//     // Start the SPI transaction
//     UCA0TXBUF = b;
// }
//
// // Wait for tx to complete
// static void txwait() {
//     // Wait for UCRXIFG, not UCTXIFG! UCTXIFG signifies that UCA0TXBUF
//     // can accept more data, not transfer completion. UCRXIFG signifies
//     // rx completion, which implies tx completion.
//     while (!(UCA0IV & UCRXIFG));
// }


static uint8_t txrx(uint8_t b) {
    // Wait until `UCA0TXBUF` can accept more data
    while (!(UCA0IFG & UCTXIFG));
    // Clear UCRXIFG so we can tell when tx/rx is complete
    UCA0IFG &= ~UCRXIFG;
    // Start the SPI transaction
    UCA0TXBUF = b;
    // Wait for tx completion
    // Wait for UCRXIFG, not UCTXIFG! UCTXIFG signifies that UCA0TXBUF
    // can accept more data, not transfer completion. UCRXIFG signifies
    // rx completion, which implies tx completion.
    while (!(UCA0IFG & UCRXIFG));
    return UCA0RXBUF;
}

// static uint8_t rx() {
//     // Dummy write
//     tx(0xFF);
//     //
//
//     UCA0TXBUF = b;
//     while (!(UCA0IV & UCTXIFG));
// }

// template <typename... Bs>
// void tx(uint8_t b, Bs... bs) {
//     tx(b);
//     tx(bs...);
// }
//
// template <size_t Len>
// void tx(uint8_t (&bs)[Len]) {
//     for (uint8_t b : bs) {
//         tx(b);
//     }
// }


static void txrx(const ICE40::Msg& msg, ICE40::Resp& resp) {
    // PA.4 = UCA0SIMO
    PASEL1 &= ~BIT4;
    PASEL0 |=  BIT4;
    
    // PA.4 level shifter direction = MSP->ICE
    PAOUT |= BIT3;
    
    txrx(msg.type);
    
    for (uint8_t b : msg.payload) {
        txrx(b);
    }
    
    // PA.4 = GPIO input
    PASEL1 &= ~BIT4;
    PASEL0 &= ~BIT4;
    
    // PA.4 level shifter direction = MSP<-ICE
    PAOUT &= ~BIT3;
    
    // 8-cycle turnaround
    txrx(0xFF);
    
    for (uint8_t& b : resp.payload) {
        b = txrx(0xFF);
    }
}

static void txrx(const ICE40::Msg& msg) {
    ICE40::Resp resp;
    txrx(msg, resp);
}



int main() {
    _sysInit();
    
    // PA.3 = GPIO output
    PAOUT  &= ~BIT3;
    PADIR  |=  BIT3;
    PASEL1 &= ~BIT3;
    PASEL0 &= ~BIT3;
    
    // PA.4 = GPIO input
    PADIR  &= ~BIT4;
    PASEL1 &= ~BIT4;
    PASEL0 &= ~BIT4;
    
    // PA.5 = UCA0SOMI
    PASEL1 &= ~BIT5;
    PASEL0 |=  BIT5;
    
    // PA.6 = UCA0CLK
    PASEL1 &= ~BIT6;
    PASEL0 |=  BIT6;
    
    // Assert USCI reset
    UCA0CTLW0 |= UCSWRST;
    
    UCA0CTLW0 |=
        // phase=0, polarity=0, MSB first, width=8-bit
        UCCKPH_0 | UCCKPL__LOW | UCMSB_1 | UC7BIT__8BIT |
        // mode=master, mode=3-pin SPI, mode=synchronous, clock=SMCLK
        UCMST__MASTER | UCMODE_0 | UCSYNC__SYNC | UCSSEL__SMCLK;
    
    // fBitClock = fBRCLK / 1;
    UCA0BRW = 0;
    // No modulation
    UCA0MCTLW = 0;
    
    // De-assert USCI reset
    UCA0CTLW0 &= ~UCSWRST;
    
    // // Reset the ICE40 SPI state machine by clocking lots of 0xFF's
    // for (uint8_t i=0; i<8; i++) {
    //     const ICE40::LEDSetMsg msg(i);
    //     txrx(msg);
    //     // __delay_cycles(16000000);
    // }
    
    for (uint8_t i=0;; i++) {
        const ICE40::LEDSetMsg msg(i);
        txrx(msg);
        __delay_cycles(16000000);
    }
    
    return 0;
}
