#include "Assert.h"

extern "C"
void _ISR_Default() {
    Assert(false);
}

[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_RESET();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_SYSNMI();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_UNMI();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_TIMER0_A0();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_TIMER0_A1();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_TIMER1_A0();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_TIMER1_A1();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_TIMER2_A0();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_TIMER2_A1();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_TIMER3_A0();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_TIMER3_A1();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_RTC();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_WDT();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_USCI_A0();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_USCI_A1();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_USCI_B0();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_ADC();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_PORT1();
[[gnu::weak, gnu::alias("_ISR_Default")]] void _ISR_PORT2();

// u16 values because reset vectors must be 16-bit, even in large memory
// model mode where pointers are 20-bit (stored as u32)
[[gnu::section(".intvec"), gnu::used]]
static uint16_t _InterruptVector[] = {
    (uint16_t)&_ISR_RESET,
    (uint16_t)&_ISR_SYSNMI,
    (uint16_t)&_ISR_UNMI,
    (uint16_t)&_ISR_TIMER0_A0,
    (uint16_t)&_ISR_TIMER0_A1,
    (uint16_t)&_ISR_TIMER1_A0,
    (uint16_t)&_ISR_TIMER1_A1,
    (uint16_t)&_ISR_TIMER2_A0,
    (uint16_t)&_ISR_TIMER2_A1,
    (uint16_t)&_ISR_TIMER3_A0,
    (uint16_t)&_ISR_TIMER3_A1,
    (uint16_t)&_ISR_RTC,
    (uint16_t)&_ISR_WDT,
    (uint16_t)&_ISR_USCI_A0,
    (uint16_t)&_ISR_USCI_A1,
    (uint16_t)&_ISR_USCI_B0,
    (uint16_t)&_ISR_ADC,
    (uint16_t)&_ISR_PORT1,
    (uint16_t)&_ISR_PORT2,
};
