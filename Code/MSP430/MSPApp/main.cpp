#include <msp430fr2422.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>

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

uint8_t RXData = 0;
uint8_t TXData = 0;

__interrupt __attribute__((interrupt(USCI_A0_VECTOR)))
static void _isrUSCIA0() {
    switch (UCA0IV) {
    case USCI_SPI_UCRXIFG:
        RXData = UCA0RXBUF;
        UCA0IFG &= ~UCRXIFG;
        // Wake up to setup next TX
        __bic_SR_register_on_exit(LPM0_bits);
        break;
    
    case USCI_SPI_UCTXIFG:
        UCA0TXBUF = TXData;
        UCA0IE &= ~UCTXIE;
        break;
    
    default:
        break;
    }
}









int main() {
    _sysInit();
    
    P1SEL0 |= BIT4 | BIT5 | BIT6;
    
    // Assert USCI reset
    UCA0CTLW0 = UCSWRST;
    
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
    
    // Enable USCI_A0 RX interrupt
    UCA0IE |= UCRXIE;
    
    TXData = 0x01;                            // Holds TX data
    
    for (;;) {
        UCA0IE |= UCTXIE;                     // Enable TX interrupt
        __bis_SR_register(LPM0_bits | GIE);   // Enable global interrupts, enter LPM0
        __no_operation();                     // For debug,Remain in LPM0
        __delay_cycles(2000);                 // Delay before next transmission
        TXData++;                             // Increment transmit data
    }
    
    return 0;
}
