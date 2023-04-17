.syntax unified
.cpu cortex-m7
.fpu softvfp
.thumb

.global VectorTable

// Vector table
.section .isr.VectorTable
// VectorTable must be 512-byte aligned (1<<9), because the table
// contains 120 words * 4 -> 480 bytes -> ceil power of 2 -> 512
.align 9
.type VectorTable, %object
VectorTable:
    .word _StackInterrupt
    .word ISR_Reset

    .word ISR_NMI
    .word ISR_HardFault
    .word ISR_MemManage
    .word ISR_BusFault
    .word ISR_UsageFault
    .word 0
    .word 0
    .word 0
    .word 0
    .word ISR_SVC
    .word ISR_DebugMon
    .word 0
    .word ISR_PendSV
    .word ISR_SysTick

    // External Interrupts
    .word    ISR_WWDG                   // Window WatchDog
    .word    ISR_PVD                    // PVD through EXTI Line detection
    .word    ISR_TAMP_STAMP             // Tamper and TimeStamps through the EXTI line
    .word    ISR_RTC_WKUP               // RTC Wakeup through the EXTI line
    .word    ISR_FLASH                  // FLASH
    .word    ISR_RCC                    // RCC
    .word    ISR_EXTI0                  // EXTI Line0
    .word    ISR_EXTI1                  // EXTI Line1
    .word    ISR_EXTI2                  // EXTI Line2
    .word    ISR_EXTI3                  // EXTI Line3
    .word    ISR_EXTI4                  // EXTI Line4
    .word    ISR_DMA1_Stream0           // DMA1 Stream 0
    .word    ISR_DMA1_Stream1           // DMA1 Stream 1
    .word    ISR_DMA1_Stream2           // DMA1 Stream 2
    .word    ISR_DMA1_Stream3           // DMA1 Stream 3
    .word    ISR_DMA1_Stream4           // DMA1 Stream 4
    .word    ISR_DMA1_Stream5           // DMA1 Stream 5
    .word    ISR_DMA1_Stream6           // DMA1 Stream 6
    .word    ISR_ADC                    // ADC1, ADC2 and ADC3s
    .word    ISR_CAN1_TX                // CAN1 TX
    .word    ISR_CAN1_RX0               // CAN1 RX0
    .word    ISR_CAN1_RX1               // CAN1 RX1
    .word    ISR_CAN1_SCE               // CAN1 SCE
    .word    ISR_EXTI9_5                // External Line[9:5]s
    .word    ISR_TIM1_BRK_TIM9          // TIM1 Break and TIM9
    .word    ISR_TIM1_UP_TIM10          // TIM1 Update and TIM10
    .word    ISR_TIM1_TRG_COM_TIM11     // TIM1 Trigger and Commutation and TIM11
    .word    ISR_TIM1_CC                // TIM1 Capture Compare
    .word    ISR_TIM2                   // TIM2
    .word    ISR_TIM3                   // TIM3
    .word    ISR_TIM4                   // TIM4
    .word    ISR_I2C1_EV                // I2C1 Event
    .word    ISR_I2C1_ER                // I2C1 Error
    .word    ISR_I2C2_EV                // I2C2 Event
    .word    ISR_I2C2_ER                // I2C2 Error
    .word    ISR_SPI1                   // SPI1
    .word    ISR_SPI2                   // SPI2
    .word    ISR_USART1                 // USART1
    .word    ISR_USART2                 // USART2
    .word    ISR_USART3                 // USART3
    .word    ISR_EXTI15_10              // External Line[15:10]s
    .word    ISR_RTC_Alarm              // RTC Alarm (A and B) through EXTI Line
    .word    ISR_OTG_FS_WKUP            // USB OTG FS Wakeup through EXTI line
    .word    ISR_TIM8_BRK_TIM12         // TIM8 Break and TIM12
    .word    ISR_TIM8_UP_TIM13          // TIM8 Update and TIM13
    .word    ISR_TIM8_TRG_COM_TIM14     // TIM8 Trigger and Commutation and TIM14
    .word    ISR_TIM8_CC                // TIM8 Capture Compare
    .word    ISR_DMA1_Stream7           // DMA1 Stream7
    .word    ISR_FMC                    // FMC
    .word    ISR_SDMMC1                 // SDMMC1
    .word    ISR_TIM5                   // TIM5
    .word    ISR_SPI3                   // SPI3
    .word    ISR_UART4                  // UART4
    .word    ISR_UART5                  // UART5
    .word    ISR_TIM6_DAC               // TIM6 and DAC1&2 underrun errors
    .word    ISR_TIM7                   // TIM7
    .word    ISR_DMA2_Stream0           // DMA2 Stream 0
    .word    ISR_DMA2_Stream1           // DMA2 Stream 1
    .word    ISR_DMA2_Stream2           // DMA2 Stream 2
    .word    ISR_DMA2_Stream3           // DMA2 Stream 3
    .word    ISR_DMA2_Stream4           // DMA2 Stream 4
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    ISR_OTG_FS                 // USB OTG FS
    .word    ISR_DMA2_Stream5           // DMA2 Stream 5
    .word    ISR_DMA2_Stream6           // DMA2 Stream 6
    .word    ISR_DMA2_Stream7           // DMA2 Stream 7
    .word    ISR_USART6                 // USART6
    .word    ISR_I2C3_EV                // I2C3 event
    .word    ISR_I2C3_ER                // I2C3 error
    .word    ISR_OTG_HS_EP1_OUT         // USB OTG HS End Point 1 Out
    .word    ISR_OTG_HS_EP1_IN          // USB OTG HS End Point 1 In
    .word    ISR_OTG_HS_WKUP            // USB OTG HS Wakeup through EXTI
    .word    ISR_OTG_HS                 // USB OTG HS
    .word    0                          // Reserved
    .word    ISR_AES                    // AES
    .word    ISR_RNG                    // RNG
    .word    ISR_FPU                    // FPU
    .word    ISR_UART7                  // UART7
    .word    ISR_UART8                  // UART8
    .word    ISR_SPI4                   // SPI4
    .word    ISR_SPI5                   // SPI5
    .word    0                          // Reserved
    .word    ISR_SAI1                   // SAI1
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    ISR_SAI2                   // SAI2
    .word    ISR_QUADSPI                // QUADSPI
    .word    ISR_LPTIM1                 // LPTIM1
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    0                          // Reserved
    .word    ISR_SDMMC2                 // SDMMC2


    // Provide weak aliases for each Exception handler to the ISR_Default.
    // As they are weak aliases, any function with the same name will override
    // this definition.

    .weak      ISR_NMI
    .thumb_set ISR_NMI,ISR_Default

    .weak      ISR_HardFault
    .thumb_set ISR_HardFault,ISR_Default

    .weak      ISR_MemManage
    .thumb_set ISR_MemManage,ISR_Default

    .weak      ISR_BusFault
    .thumb_set ISR_BusFault,ISR_Default

    .weak      ISR_UsageFault
    .thumb_set ISR_UsageFault,ISR_Default

    .weak      ISR_SVC
    .thumb_set ISR_SVC,ISR_Default

    .weak      ISR_DebugMon
    .thumb_set ISR_DebugMon,ISR_Default

    .weak      ISR_PendSV
    .thumb_set ISR_PendSV,ISR_Default

    .weak      ISR_SysTick
    .thumb_set ISR_SysTick,ISR_Default

    .weak      ISR_WWDG
    .thumb_set ISR_WWDG,ISR_Default

    .weak      ISR_PVD
    .thumb_set ISR_PVD,ISR_Default

    .weak      ISR_TAMP_STAMP
    .thumb_set ISR_TAMP_STAMP,ISR_Default

    .weak      ISR_RTC_WKUP
    .thumb_set ISR_RTC_WKUP,ISR_Default

    .weak      ISR_FLASH
    .thumb_set ISR_FLASH,ISR_Default

    .weak      ISR_RCC
    .thumb_set ISR_RCC,ISR_Default

    .weak      ISR_EXTI0
    .thumb_set ISR_EXTI0,ISR_Default

    .weak      ISR_EXTI1
    .thumb_set ISR_EXTI1,ISR_Default

    .weak      ISR_EXTI2
    .thumb_set ISR_EXTI2,ISR_Default

    .weak      ISR_EXTI3
    .thumb_set ISR_EXTI3,ISR_Default

    .weak      ISR_EXTI4
    .thumb_set ISR_EXTI4,ISR_Default

    .weak      ISR_DMA1_Stream0
    .thumb_set ISR_DMA1_Stream0,ISR_Default

    .weak      ISR_DMA1_Stream1
    .thumb_set ISR_DMA1_Stream1,ISR_Default

    .weak      ISR_DMA1_Stream2
    .thumb_set ISR_DMA1_Stream2,ISR_Default

    .weak      ISR_DMA1_Stream3
    .thumb_set ISR_DMA1_Stream3,ISR_Default

    .weak      ISR_DMA1_Stream4
    .thumb_set ISR_DMA1_Stream4,ISR_Default

    .weak      ISR_DMA1_Stream5
    .thumb_set ISR_DMA1_Stream5,ISR_Default

    .weak      ISR_DMA1_Stream6
    .thumb_set ISR_DMA1_Stream6,ISR_Default

    .weak      ISR_ADC
    .thumb_set ISR_ADC,ISR_Default

    .weak      ISR_CAN1_TX
    .thumb_set ISR_CAN1_TX,ISR_Default

    .weak      ISR_CAN1_RX0
    .thumb_set ISR_CAN1_RX0,ISR_Default

    .weak      ISR_CAN1_RX1
    .thumb_set ISR_CAN1_RX1,ISR_Default

    .weak      ISR_CAN1_SCE
    .thumb_set ISR_CAN1_SCE,ISR_Default

    .weak      ISR_EXTI9_5
    .thumb_set ISR_EXTI9_5,ISR_Default

    .weak      ISR_TIM1_BRK_TIM9
    .thumb_set ISR_TIM1_BRK_TIM9,ISR_Default

    .weak      ISR_TIM1_UP_TIM10
    .thumb_set ISR_TIM1_UP_TIM10,ISR_Default

    .weak      ISR_TIM1_TRG_COM_TIM11
    .thumb_set ISR_TIM1_TRG_COM_TIM11,ISR_Default

    .weak      ISR_TIM1_CC
    .thumb_set ISR_TIM1_CC,ISR_Default

    .weak      ISR_TIM2
    .thumb_set ISR_TIM2,ISR_Default

    .weak      ISR_TIM3
    .thumb_set ISR_TIM3,ISR_Default

    .weak      ISR_TIM4
    .thumb_set ISR_TIM4,ISR_Default

    .weak      ISR_I2C1_EV
    .thumb_set ISR_I2C1_EV,ISR_Default

    .weak      ISR_I2C1_ER
    .thumb_set ISR_I2C1_ER,ISR_Default

    .weak      ISR_I2C2_EV
    .thumb_set ISR_I2C2_EV,ISR_Default

    .weak      ISR_I2C2_ER
    .thumb_set ISR_I2C2_ER,ISR_Default

    .weak      ISR_SPI1
    .thumb_set ISR_SPI1,ISR_Default

    .weak      ISR_SPI2
    .thumb_set ISR_SPI2,ISR_Default

    .weak      ISR_USART1
    .thumb_set ISR_USART1,ISR_Default

    .weak      ISR_USART2
    .thumb_set ISR_USART2,ISR_Default

    .weak      ISR_USART3
    .thumb_set ISR_USART3,ISR_Default

    .weak      ISR_EXTI15_10
    .thumb_set ISR_EXTI15_10,ISR_Default

    .weak      ISR_RTC_Alarm
    .thumb_set ISR_RTC_Alarm,ISR_Default

    .weak      ISR_OTG_FS_WKUP
    .thumb_set ISR_OTG_FS_WKUP,ISR_Default

    .weak      ISR_TIM8_BRK_TIM12
    .thumb_set ISR_TIM8_BRK_TIM12,ISR_Default

    .weak      ISR_TIM8_UP_TIM13
    .thumb_set ISR_TIM8_UP_TIM13,ISR_Default

    .weak      ISR_TIM8_TRG_COM_TIM14
    .thumb_set ISR_TIM8_TRG_COM_TIM14,ISR_Default

    .weak      ISR_TIM8_CC
    .thumb_set ISR_TIM8_CC,ISR_Default

    .weak      ISR_DMA1_Stream7
    .thumb_set ISR_DMA1_Stream7,ISR_Default

    .weak      ISR_FMC
    .thumb_set ISR_FMC,ISR_Default

    .weak      ISR_SDMMC1
    .thumb_set ISR_SDMMC1,ISR_Default

    .weak      ISR_TIM5
    .thumb_set ISR_TIM5,ISR_Default

    .weak      ISR_SPI3
    .thumb_set ISR_SPI3,ISR_Default

    .weak      ISR_UART4
    .thumb_set ISR_UART4,ISR_Default

    .weak      ISR_UART5
    .thumb_set ISR_UART5,ISR_Default

    .weak      ISR_TIM6_DAC
    .thumb_set ISR_TIM6_DAC,ISR_Default

    .weak      ISR_TIM7
    .thumb_set ISR_TIM7,ISR_Default

    .weak      ISR_DMA2_Stream0
    .thumb_set ISR_DMA2_Stream0,ISR_Default

    .weak      ISR_DMA2_Stream1
    .thumb_set ISR_DMA2_Stream1,ISR_Default

    .weak      ISR_DMA2_Stream2
    .thumb_set ISR_DMA2_Stream2,ISR_Default

    .weak      ISR_DMA2_Stream3
    .thumb_set ISR_DMA2_Stream3,ISR_Default

    .weak      ISR_DMA2_Stream4
    .thumb_set ISR_DMA2_Stream4,ISR_Default

    .weak      ISR_OTG_FS
    .thumb_set ISR_OTG_FS,ISR_Default

    .weak      ISR_DMA2_Stream5
    .thumb_set ISR_DMA2_Stream5,ISR_Default

    .weak      ISR_DMA2_Stream6
    .thumb_set ISR_DMA2_Stream6,ISR_Default

    .weak      ISR_DMA2_Stream7
    .thumb_set ISR_DMA2_Stream7,ISR_Default

    .weak      ISR_USART6
    .thumb_set ISR_USART6,ISR_Default

    .weak      ISR_I2C3_EV
    .thumb_set ISR_I2C3_EV,ISR_Default

    .weak      ISR_I2C3_ER
    .thumb_set ISR_I2C3_ER,ISR_Default

    .weak      ISR_OTG_HS_EP1_OUT
    .thumb_set ISR_OTG_HS_EP1_OUT,ISR_Default

    .weak      ISR_OTG_HS_EP1_IN
    .thumb_set ISR_OTG_HS_EP1_IN,ISR_Default

    .weak      ISR_OTG_HS_WKUP
    .thumb_set ISR_OTG_HS_WKUP,ISR_Default

    .weak      ISR_OTG_HS
    .thumb_set ISR_OTG_HS,ISR_Default

    .weak      ISR_AES
    .thumb_set ISR_AES,ISR_Default

    .weak      ISR_RNG
    .thumb_set ISR_RNG,ISR_Default

    .weak      ISR_FPU
    .thumb_set ISR_FPU,ISR_Default

    .weak      ISR_UART7
    .thumb_set ISR_UART7,ISR_Default

    .weak      ISR_UART8
    .thumb_set ISR_UART8,ISR_Default

    .weak      ISR_SPI4
    .thumb_set ISR_SPI4,ISR_Default

    .weak      ISR_SPI5
    .thumb_set ISR_SPI5,ISR_Default

    .weak      ISR_SAI1
    .thumb_set ISR_SAI1,ISR_Default

    .weak      ISR_SAI2
    .thumb_set ISR_SAI2,ISR_Default

    .weak      ISR_QUADSPI
    .thumb_set ISR_QUADSPI,ISR_Default

    .weak      ISR_LPTIM1
    .thumb_set ISR_LPTIM1,ISR_Default

    .weak      ISR_SDMMC2
    .thumb_set ISR_SDMMC2,ISR_Default
    
    .size VectorTable, .-VectorTable

// Default ISR handler
.section .isr
.type ISR_Default, %function
ISR_Default:
    b  ISR_Default
