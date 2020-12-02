#include "stm32f7xx.h"
#include "System.h"

extern "C" __attribute__((section(".isr"))) void ISR_NMI() {}
extern "C" __attribute__((section(".isr"))) void ISR_HardFault() { for (;;); }
extern "C" __attribute__((section(".isr"))) void ISR_MemManage() { for (;;); }
extern "C" __attribute__((section(".isr"))) void ISR_BusFault() { for (;;); }
extern "C" __attribute__((section(".isr"))) void ISR_UsageFault() { for (;;); }
extern "C" __attribute__((section(".isr"))) void ISR_SVC() {}
extern "C" __attribute__((section(".isr"))) void ISR_DebugMon() {}
extern "C" __attribute__((section(".isr"))) void ISR_PendSV() {}

extern "C" __attribute__((section(".isr"))) void ISR_SysTick() {
    HAL_IncTick();
}

extern "C" __attribute__((section(".isr"))) void ISR_OTG_HS() {
    Sys._usb._isr();
}

extern "C" __attribute__((section(".isr"))) void ISR_QUADSPI() {
    Sys._qspi._isrQSPI();
}

extern "C" __attribute__((section(".isr"))) void ISR_DMA2_Stream7() {
    Sys._qspi._isrDMA();
}
