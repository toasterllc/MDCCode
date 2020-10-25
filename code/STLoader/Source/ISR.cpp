#include "stm32f7xx.h"
#include "System.h"

extern "C" void ISR_NMI() {}
extern "C" void ISR_HardFault() { for (;;); }
extern "C" void ISR_MemManage() { for (;;); }
extern "C" void ISR_BusFault() { for (;;); }
extern "C" void ISR_UsageFault() { for (;;); }
extern "C" void ISR_SVC() {}
extern "C" void ISR_DebugMon() {}
extern "C" void ISR_PendSV() {}

extern "C" void ISR_SysTick() {
    HAL_IncTick();
}

extern "C" void ISR_OTG_HS() {
    Sys.usb._isr();
}

extern "C" void ISR_QUADSPI() {
    Sys.qspi._isr();
}
