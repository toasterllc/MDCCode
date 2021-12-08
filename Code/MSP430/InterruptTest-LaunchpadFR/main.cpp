#include <msp430fr2433.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>

class MyClass {
public:
    MyClass() {
        for (volatile int i=0; i<100; i++);
    }
    
private:
    static inline bool _ColdStart = false;
    
    __attribute__((section(".crt_0401_startup"), naked, used))
    static void _startup() {
        _ColdStart = (SYSRSTIV != SYSRSTIV_LPM5WU);
    }
    
    uint32_t _testVar = 0xCAFEBABE;
};

__attribute__((interrupt(PORT2_VECTOR)))
void _isr_port2() {
    // Accessing `P2IV` automatically clears the highest-priority interrupt
    switch (__even_in_range(P2IV, P2IV_P2IFG3)) {
    case P2IV_P2IFG3:
        PAOUT ^= 1<<0;
        break;
    
    default:
        break;
    }
}

volatile int myInt = 0;

__attribute__((section(".bakmem")))
MyClass myClass;

int main() {
    WDTCTL = WDTPW | WDTHOLD;
    
    PM5CTL0 &= ~LOCKLPM5;
    
    PAOUT   = 0x0801;
    PADIR   = 0x0001;
    PASEL0  = 0x0000;
    PASEL1  = 0x0000;
    PAREN   = 0x0800;
    PAIE    = 0x0800;
    PAIES   = 0x0000;
    
    // __bis_SR_register(GIE);
    // for (;;);
    //
    // for (;;) {
    //     __delay_cycles(1000000);
    //     __bis_SR_register(GIE);
    //     __bic_SR_register(GIE);
    // }
    
    // // Enable interrupts + go to sleep
    __bis_SR_register(GIE);
    
    for (volatile int i=0;; i++);
}
