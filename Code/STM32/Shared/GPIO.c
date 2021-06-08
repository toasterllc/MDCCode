#include "stm32f7xx.h"

#define _Stringify(s) #s
#define Stringify(s) _Stringify(s)

__asm__(".global GPIOPortA ; .equ GPIOPortA, " Stringify(GPIOA_BASE));
__asm__(".global GPIOPortB ; .equ GPIOPortB, " Stringify(GPIOB_BASE));
__asm__(".global GPIOPortC ; .equ GPIOPortC, " Stringify(GPIOC_BASE));
__asm__(".global GPIOPortD ; .equ GPIOPortD, " Stringify(GPIOD_BASE));
__asm__(".global GPIOPortE ; .equ GPIOPortE, " Stringify(GPIOE_BASE));
__asm__(".global GPIOPortF ; .equ GPIOPortF, " Stringify(GPIOF_BASE));
__asm__(".global GPIOPortG ; .equ GPIOPortG, " Stringify(GPIOG_BASE));
__asm__(".global GPIOPortH ; .equ GPIOPortH, " Stringify(GPIOH_BASE));
__asm__(".global GPIOPortI ; .equ GPIOPortI, " Stringify(GPIOI_BASE));
