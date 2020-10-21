#include "main.h"
#include "stm32f7xx_it.h"

void ISR_NMI() {
}

void ISR_HardFault() {
  for (;;);
}

void ISR_MemManage() {
  for (;;);
}

void ISR_BusFault() {
  for (;;);
}

void ISR_UsageFault() {
  for (;;);
}

void ISR_SVC() {
  for (;;);
}

void ISR_DebugMon() {
    for (;;);
}

void ISR_PendSV() {
    for (;;);
}

void ISR_SysTick() {
    HAL_IncTick();
}

void ISR_OTG_HS() {
    extern PCD_HandleTypeDef hpcd_USB_OTG_HS;
    ISR_HAL_PCD(&hpcd_USB_OTG_HS);
}
