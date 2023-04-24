#include <msp430.h>
#include <stdint.h>

static void MCLK16MHz() {
    const uint16_t* CSCTL0Cal16MHz = (uint16_t*)0x1A22;
    
    // Configure one FRAM wait state if MCLK > 8MHz.
    // This must happen before configuring the clock system.
    FRCTL0 = FRCTLPW | NWAITS_1;
    
    // Disable FLL
    __bis_SR_register(SCG0);
        // Set REFO as FLL reference source
        CSCTL3 |= SELREF__REFOCLK;
        // Clear DCO and MOD registers
        CSCTL0 = 0;
        // Clear DCO frequency select bits first
        CSCTL1 &= ~(DCORSEL_7);
        
        // Select 16 MHz
        CSCTL1 |= DCORSEL_5;
        
        // Set DCOCLKDIV based on T_MCLKFreqHz and REFOCLKFreqHz
        CSCTL2 = FLLD_0 | (((uint32_t)16000000/(uint32_t)32768)-1);
        
        // Special case: use the factory-calibrated values for CSCTL0 if one is available for the target frequency
        // This significantly speeds up the FLL lock time; without this technique, it takes ~200ms to get an FLL
        // lock (datasheet specifies 280ms as typical). Using the factory-calibrated value, an FLL lock takes 800us.
        CSCTL0 = *CSCTL0Cal16MHz;
        
        // Wait 3 cycles to take effect
        __delay_cycles(3);
    // Enable FLL
    __bic_SR_register(SCG0);
    
    // Special case: if we're using one of the factory-calibrated values for CSCTL0 (see above),
    // we need to delay 10 REFOCLK cycles. We do this by temporarily switching MCLK to be sourced
    // by REFOCLK, and waiting 10 cycles.
    // This technique is prescribed by "MSP430FR2xx/FR4xx DCO+FLL Applications Guide", and shown
    // by the "MSP430FR2x5x_FLL_FastLock_24MHz-16MHz.c" example code.
    CSCTL4 |= SELMS__REFOCLK;
    __delay_cycles(10);
    
    // Wait until FLL locks
    while (CSCTL7 & (FLLUNLOCK0 | FLLUNLOCK1));
}

static volatile uint32_t iv = 0;

int main() {
    // Stop watchdog timer
    WDTCTL = WDTPW | WDTHOLD;
    
    // Set MCLK to 16 MHz
//    MCLK16MHz();
    
    P1OUT = 0;
    P1DIR |= BIT0 | BIT1;
    PM5CTL0 &= ~LOCKLPM5;
    
    #define MaxVal      1
    #define OverflowVal (MaxVal+1)
    RTCMOD = MaxVal;
    RTCCTL = RTCSS__VLOCLK | RTCPS__1 | RTCSR;
//    RTCCTL = RTCSS__VLOCLK | RTCPS__1 | RTCSR;
    // "TI recommends clearing the RTCIFG bit by reading the RTCIV register
    // before enabling the RTC counter interrupt."
    RTCIV;
    // Enable RTC interrupts
    RTCCTL |= RTCIE;
    
    __delay_cycles(1000000);
    
    // Wait for RTC to start
    while (!RTCCNT);
    
//    __delay_cycles(1000000);
    
    for (;;) {
        volatile uint16_t count = RTCCNT;
        if (count == OverflowVal+1) {
//            __delay_cycles(500000);
//            __delay_cycles(1600);
            
            if (!(RTCCTL & RTCIF)) {
                P1OUT |= BIT1;
            }
            
            // Clear interrupt
            iv = RTCIV;
            
            // Wait until RTCCNT escapes 0
            while (!RTCCNT);
        }
        
//        P1OUT ^= BIT1;
//        __delay_cycles(1000000);
    }
    
//    for (;;) {
//        uint16_t count = RTCCNT;
//        if (!count) {
//            P1OUT |= BIT1;
//        }
//    }
}














//#include <msp430.h>
//#include <stdint.h>
//
//static volatile uint32_t iv = 0;
//
//int main() {
//    // Stop watchdog timer
//    WDTCTL = WDTPW | WDTHOLD;
//    
//    P1OUT = 0;
//    P1DIR |= BIT0 | BIT1;
//    PM5CTL0 &= ~LOCKLPM5;
//    
//    RTCMOD = 32;
//    RTCCTL = RTCSS__VLOCLK | RTCSR | RTCPS__1024 | RTCIE;
//    
//    __delay_cycles(1000000);
//    
////    // Wait for RTC to start
////    while (!RTCCNT);
//    
//    for (;;) {
//        volatile uint16_t count = RTCCNT;
//        if (!count) {
//            P1OUT ^= BIT0;
//            
//            if (!(RTCCTL & RTCIF)) {
//                P1OUT |= BIT1;
//            }
//            
//            // Clear interrupt
//            iv = RTCIV;
//            
//            // Wait until RTCCNT escapes 0
//            while (!RTCCNT);
//        }
//        
////        P1OUT ^= BIT1;
////        __delay_cycles(1000000);
//    }
//    
////    for (;;) {
////        uint16_t count = RTCCNT;
////        if (!count) {
////            P1OUT |= BIT1;
////        }
////    }
//}
//
////#pragma vector=RTC_VECTOR
////__interrupt void RTC_ISR(void)
////{
////    P1OUT ^= BIT0;
////}
//
//
//
//
//
//
//
//
//
//
//
//
////#include <msp430.h>
////#include <stdint.h>
////
////int main() {
////    // Stop watchdog timer
////    WDTCTL = WDTPW | WDTHOLD;
////    
////    P1OUT = 0;
////    P1DIR |= BIT0 | BIT1;
////    PM5CTL0 &= ~LOCKLPM5;
////    
////    RTCMOD = 2;
////    RTCCTL = RTCSS__VLOCLK | RTCSR | RTCPS__1024 | RTCIE;
////    
////    // Enable interrupts
////    __bis_SR_register(GIE);
////    for (;;) {
////        __bic_SR_register(GIE);
////        {
////            uint16_t count = RTCCNT;
////            if (!count) {
////                if (!(RTCCTL & RTCIF)) {
////                    P1OUT |= BIT1;
////                }
//////                __delay_cycles(100000);
////            }
////            
////            
////            
////        }
////        __bis_SR_register(GIE);
////        
//////        P1OUT ^= BIT1;
//////        __delay_cycles(1000000);
////    }
////    
//////    for (;;) {
//////        uint16_t count = RTCCNT;
//////        if (!count) {
//////            P1OUT |= BIT1;
//////        }
//////    }
////}
////
//////#pragma vector=RTC_VECTOR
//////__interrupt void RTC_ISR(void)
//////{
//////    switch(__even_in_range(RTCIV,RTCIV_RTCIF))
//////    {
//////        case  RTCIV_NONE:   break;          // No interrupt
//////        case  RTCIV_RTCIF:                  // RTC Overflow
//////            P1OUT ^= BIT0;
//////            break;
//////        default: break;
//////    }
//////}
////
