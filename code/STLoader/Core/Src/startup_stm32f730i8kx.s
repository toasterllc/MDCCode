.syntax unified
.cpu cortex-m7
.fpu softvfp
.thumb

.global VectorTable
.global DefaultHandler

/* start address for the initialization values of the .data section. 
defined in linker script */
.word _sidata
/* start address for the .data section. defined in linker script */  
.word _sdata
/* end address for the .data section. defined in linker script */
.word _edata
/* start address for the .bss section. defined in linker script */
.word _sbss
/* end address for the .bss section. defined in linker script */
.word _ebss
/* stack used for SystemInit_ExtMemCtl; always internal RAM used */

.section .text.ResetHandler
.weak ResetHandler
.type ResetHandler, %function
ResetHandler:
    ldr sp, =_estack /* set stack pointer */
    bl SystemInit
    bx lr
.size ResetHandler, .-ResetHandler


.section .text.DefaultHandler,"ax",%progbits
DefaultHandler:
Infinite_Loop:
    b  Infinite_Loop
.size DefaultHandler, .-DefaultHandler


// Vector table
.section .isr_vector,"a",%progbits
.type VectorTable, %object
.size VectorTable, .-VectorTable

VectorTable:
  .word _estack
  .word ResetHandler

  .word NMI_Handler
  .word HardFault_Handler
  .word MemManage_Handler
  .word BusFault_Handler
  .word UsageFault_Handler
  .word 0
  .word 0
  .word 0
  .word 0
  .word SVC_Handler
  .word DebugMon_Handler
  .word 0
  .word PendSV_Handler
  .word SysTick_Handler
  
  /* External Interrupts */
  .word    ISR_WWDG                   /* Window WatchDog              */                                        
  .word    ISR_PVD                    /* PVD through EXTI Line detection */                        
  .word    ISR_TAMP_STAMP             /* Tamper and TimeStamps through the EXTI line */            
  .word    ISR_RTC_WKUP               /* RTC Wakeup through the EXTI line */                      
  .word    ISR_FLASH                  /* FLASH                        */                                          
  .word    ISR_RCC                    /* RCC                          */                                            
  .word    ISR_EXTI0                  /* EXTI Line0                   */                        
  .word    ISR_EXTI1                  /* EXTI Line1                   */                          
  .word    ISR_EXTI2                  /* EXTI Line2                   */                          
  .word    ISR_EXTI3                  /* EXTI Line3                   */                          
  .word    ISR_EXTI4                  /* EXTI Line4                   */                          
  .word    ISR_DMA1_Stream0           /* DMA1 Stream 0                */                  
  .word    ISR_DMA1_Stream1           /* DMA1 Stream 1                */                   
  .word    ISR_DMA1_Stream2           /* DMA1 Stream 2                */                   
  .word    ISR_DMA1_Stream3           /* DMA1 Stream 3                */                   
  .word    ISR_DMA1_Stream4           /* DMA1 Stream 4                */                   
  .word    ISR_DMA1_Stream5           /* DMA1 Stream 5                */                   
  .word    ISR_DMA1_Stream6           /* DMA1 Stream 6                */                   
  .word    ISR_ADC                    /* ADC1, ADC2 and ADC3s         */                   
  .word    ISR_CAN1_TX                /* CAN1 TX                      */                         
  .word    ISR_CAN1_RX0               /* CAN1 RX0                     */                          
  .word    ISR_CAN1_RX1               /* CAN1 RX1                     */                          
  .word    ISR_CAN1_SCE               /* CAN1 SCE                     */                          
  .word    ISR_EXTI9_5                /* External Line[9:5]s          */                          
  .word    ISR_TIM1_BRK_TIM9          /* TIM1 Break and TIM9          */         
  .word    ISR_TIM1_UP_TIM10          /* TIM1 Update and TIM10        */         
  .word    ISR_TIM1_TRG_COM_TIM11     /* TIM1 Trigger and Commutation and TIM11 */
  .word    ISR_TIM1_CC                /* TIM1 Capture Compare         */                          
  .word    ISR_TIM2                   /* TIM2                         */                   
  .word    ISR_TIM3                   /* TIM3                         */                   
  .word    ISR_TIM4                   /* TIM4                         */                   
  .word    ISR_I2C1_EV                /* I2C1 Event                   */                          
  .word    ISR_I2C1_ER                /* I2C1 Error                   */                          
  .word    ISR_I2C2_EV                /* I2C2 Event                   */                          
  .word    ISR_I2C2_ER                /* I2C2 Error                   */                            
  .word    ISR_SPI1                   /* SPI1                         */                   
  .word    ISR_SPI2                   /* SPI2                         */                   
  .word    ISR_USART1                 /* USART1                       */                   
  .word    ISR_USART2                 /* USART2                       */                   
  .word    ISR_USART3                 /* USART3                       */                   
  .word    ISR_EXTI15_10              /* External Line[15:10]s        */                          
  .word    ISR_RTC_Alarm              /* RTC Alarm (A and B) through EXTI Line */                 
  .word    ISR_OTG_FS_WKUP            /* USB OTG FS Wakeup through EXTI line */                       
  .word    ISR_TIM8_BRK_TIM12         /* TIM8 Break and TIM12         */         
  .word    ISR_TIM8_UP_TIM13          /* TIM8 Update and TIM13        */         
  .word    ISR_TIM8_TRG_COM_TIM14     /* TIM8 Trigger and Commutation and TIM14 */
  .word    ISR_TIM8_CC                /* TIM8 Capture Compare         */                          
  .word    ISR_DMA1_Stream7           /* DMA1 Stream7                 */                          
  .word    ISR_FMC                    /* FMC                          */                   
  .word    ISR_SDMMC1                 /* SDMMC1                       */                   
  .word    ISR_TIM5                   /* TIM5                         */                   
  .word    ISR_SPI3                   /* SPI3                         */                   
  .word    ISR_UART4                  /* UART4                        */                   
  .word    ISR_UART5                  /* UART5                        */                   
  .word    ISR_TIM6_DAC               /* TIM6 and DAC1&2 underrun errors */                   
  .word    ISR_TIM7                   /* TIM7                         */
  .word    ISR_DMA2_Stream0           /* DMA2 Stream 0                */                   
  .word    ISR_DMA2_Stream1           /* DMA2 Stream 1                */                   
  .word    ISR_DMA2_Stream2           /* DMA2 Stream 2                */                   
  .word    ISR_DMA2_Stream3           /* DMA2 Stream 3                */                   
  .word    ISR_DMA2_Stream4           /* DMA2 Stream 4                */                   
  .word    0                                 /* Reserved                     */                   
  .word    0                                 /* Reserved                     */                    
  .word    0                                 /* Reserved                     */                          
  .word    0                                 /* Reserved                     */                          
  .word    0                                 /* Reserved                     */                          
  .word    0                                 /* Reserved                     */                          
  .word    ISR_OTG_FS                 /* USB OTG FS                   */                   
  .word    ISR_DMA2_Stream5           /* DMA2 Stream 5                */                   
  .word    ISR_DMA2_Stream6           /* DMA2 Stream 6                */                   
  .word    ISR_DMA2_Stream7           /* DMA2 Stream 7                */                   
  .word    ISR_USART6                 /* USART6                       */                    
  .word    ISR_I2C3_EV                /* I2C3 event                   */                          
  .word    ISR_I2C3_ER                /* I2C3 error                   */                          
  .word    ISR_OTG_HS_EP1_OUT         /* USB OTG HS End Point 1 Out   */                   
  .word    ISR_OTG_HS_EP1_IN          /* USB OTG HS End Point 1 In    */                   
  .word    ISR_OTG_HS_WKUP            /* USB OTG HS Wakeup through EXTI */                         
  .word    ISR_OTG_HS                 /* USB OTG HS                   */                   
  .word    0                                 /* Reserved                     */                   
  .word    ISR_AES                    /* AES                          */                   
  .word    ISR_RNG                    /* RNG                          */
  .word    ISR_FPU                    /* FPU                          */
  .word    ISR_UART7                  /* UART7                        */      
  .word    ISR_UART8                  /* UART8                        */
  .word    ISR_SPI4                   /* SPI4                         */
  .word    ISR_SPI5                   /* SPI5                         */
  .word    0                                 /* Reserved                     */
  .word    ISR_SAI1                   /* SAI1                         */
  .word    0                                 /* Reserved                     */
  .word    0                                 /* Reserved                     */
  .word    0                                 /* Reserved                     */
  .word    ISR_SAI2                   /* SAI2                         */
  .word    ISR_QUADSPI                /* QUADSPI                      */
  .word    ISR_LPTIM1                 /* LPTIM1                       */
  .word    0                                 /* Reserved                     */
  .word    0                                 /* Reserved                     */
  .word    0                                 /* Reserved                     */
  .word    0                                 /* Reserved                     */
  .word    0                                 /* Reserved                     */
  .word    0                                 /* Reserved                     */
  .word    0                                 /* Reserved                     */
  .word    0                                 /* Reserved                     */
  .word    0                                 /* Reserved                     */
  .word    ISR_SDMMC2                 /* SDMMC2                       */ 
  
/*******************************************************************************
*
* Provide weak aliases for each Exception handler to the DefaultHandler. 
* As they are weak aliases, any function with the same name will override 
* this definition.
* 
*******************************************************************************/
   .weak      NMI_Handler
   .thumb_set NMI_Handler,DefaultHandler
  
   .weak      HardFault_Handler
   .thumb_set HardFault_Handler,DefaultHandler
  
   .weak      MemManage_Handler
   .thumb_set MemManage_Handler,DefaultHandler
  
   .weak      BusFault_Handler
   .thumb_set BusFault_Handler,DefaultHandler

   .weak      UsageFault_Handler
   .thumb_set UsageFault_Handler,DefaultHandler

   .weak      SVC_Handler
   .thumb_set SVC_Handler,DefaultHandler

   .weak      DebugMon_Handler
   .thumb_set DebugMon_Handler,DefaultHandler

   .weak      PendSV_Handler
   .thumb_set PendSV_Handler,DefaultHandler

   .weak      SysTick_Handler
   .thumb_set SysTick_Handler,DefaultHandler              
  
   .weak      ISR_WWDG                   
   .thumb_set ISR_WWDG,DefaultHandler      
                  
   .weak      ISR_PVD      
   .thumb_set ISR_PVD,DefaultHandler
               
   .weak      ISR_TAMP_STAMP            
   .thumb_set ISR_TAMP_STAMP,DefaultHandler
            
   .weak      ISR_RTC_WKUP                  
   .thumb_set ISR_RTC_WKUP,DefaultHandler
            
   .weak      ISR_FLASH         
   .thumb_set ISR_FLASH,DefaultHandler
                  
   .weak      ISR_RCC      
   .thumb_set ISR_RCC,DefaultHandler
                  
   .weak      ISR_EXTI0         
   .thumb_set ISR_EXTI0,DefaultHandler
                  
   .weak      ISR_EXTI1         
   .thumb_set ISR_EXTI1,DefaultHandler
                     
   .weak      ISR_EXTI2         
   .thumb_set ISR_EXTI2,DefaultHandler 
                 
   .weak      ISR_EXTI3         
   .thumb_set ISR_EXTI3,DefaultHandler
                        
   .weak      ISR_EXTI4         
   .thumb_set ISR_EXTI4,DefaultHandler
                  
   .weak      ISR_DMA1_Stream0               
   .thumb_set ISR_DMA1_Stream0,DefaultHandler
         
   .weak      ISR_DMA1_Stream1               
   .thumb_set ISR_DMA1_Stream1,DefaultHandler
                  
   .weak      ISR_DMA1_Stream2               
   .thumb_set ISR_DMA1_Stream2,DefaultHandler
                  
   .weak      ISR_DMA1_Stream3               
   .thumb_set ISR_DMA1_Stream3,DefaultHandler 
                 
   .weak      ISR_DMA1_Stream4              
   .thumb_set ISR_DMA1_Stream4,DefaultHandler
                  
   .weak      ISR_DMA1_Stream5               
   .thumb_set ISR_DMA1_Stream5,DefaultHandler
                  
   .weak      ISR_DMA1_Stream6               
   .thumb_set ISR_DMA1_Stream6,DefaultHandler
                  
   .weak      ISR_ADC      
   .thumb_set ISR_ADC,DefaultHandler
               
   .weak      ISR_CAN1_TX   
   .thumb_set ISR_CAN1_TX,DefaultHandler
            
   .weak      ISR_CAN1_RX0                  
   .thumb_set ISR_CAN1_RX0,DefaultHandler
                           
   .weak      ISR_CAN1_RX1                  
   .thumb_set ISR_CAN1_RX1,DefaultHandler
            
   .weak      ISR_CAN1_SCE                  
   .thumb_set ISR_CAN1_SCE,DefaultHandler
            
   .weak      ISR_EXTI9_5   
   .thumb_set ISR_EXTI9_5,DefaultHandler
            
   .weak      ISR_TIM1_BRK_TIM9            
   .thumb_set ISR_TIM1_BRK_TIM9,DefaultHandler
            
   .weak      ISR_TIM1_UP_TIM10            
   .thumb_set ISR_TIM1_UP_TIM10,DefaultHandler

   .weak      ISR_TIM1_TRG_COM_TIM11      
   .thumb_set ISR_TIM1_TRG_COM_TIM11,DefaultHandler
      
   .weak      ISR_TIM1_CC   
   .thumb_set ISR_TIM1_CC,DefaultHandler
                  
   .weak      ISR_TIM2            
   .thumb_set ISR_TIM2,DefaultHandler
                  
   .weak      ISR_TIM3            
   .thumb_set ISR_TIM3,DefaultHandler
                  
   .weak      ISR_TIM4            
   .thumb_set ISR_TIM4,DefaultHandler
                  
   .weak      ISR_I2C1_EV   
   .thumb_set ISR_I2C1_EV,DefaultHandler
                     
   .weak      ISR_I2C1_ER   
   .thumb_set ISR_I2C1_ER,DefaultHandler
                     
   .weak      ISR_I2C2_EV   
   .thumb_set ISR_I2C2_EV,DefaultHandler
                  
   .weak      ISR_I2C2_ER   
   .thumb_set ISR_I2C2_ER,DefaultHandler
                           
   .weak      ISR_SPI1            
   .thumb_set ISR_SPI1,DefaultHandler
                        
   .weak      ISR_SPI2            
   .thumb_set ISR_SPI2,DefaultHandler
                  
   .weak      ISR_USART1      
   .thumb_set ISR_USART1,DefaultHandler
                     
   .weak      ISR_USART2      
   .thumb_set ISR_USART2,DefaultHandler
                     
   .weak      ISR_USART3      
   .thumb_set ISR_USART3,DefaultHandler
                  
   .weak      ISR_EXTI15_10               
   .thumb_set ISR_EXTI15_10,DefaultHandler
               
   .weak      ISR_RTC_Alarm               
   .thumb_set ISR_RTC_Alarm,DefaultHandler
            
   .weak      ISR_OTG_FS_WKUP         
   .thumb_set ISR_OTG_FS_WKUP,DefaultHandler
            
   .weak      ISR_TIM8_BRK_TIM12         
   .thumb_set ISR_TIM8_BRK_TIM12,DefaultHandler
         
   .weak      ISR_TIM8_UP_TIM13            
   .thumb_set ISR_TIM8_UP_TIM13,DefaultHandler
         
   .weak      ISR_TIM8_TRG_COM_TIM14      
   .thumb_set ISR_TIM8_TRG_COM_TIM14,DefaultHandler
      
   .weak      ISR_TIM8_CC   
   .thumb_set ISR_TIM8_CC,DefaultHandler
                  
   .weak      ISR_DMA1_Stream7               
   .thumb_set ISR_DMA1_Stream7,DefaultHandler
                     
   .weak      ISR_FMC            
   .thumb_set ISR_FMC,DefaultHandler
                     
   .weak      ISR_SDMMC1            
   .thumb_set ISR_SDMMC1,DefaultHandler
                     
   .weak      ISR_TIM5            
   .thumb_set ISR_TIM5,DefaultHandler
                     
   .weak      ISR_SPI3            
   .thumb_set ISR_SPI3,DefaultHandler
                     
   .weak      ISR_UART4         
   .thumb_set ISR_UART4,DefaultHandler
                  
   .weak      ISR_UART5         
   .thumb_set ISR_UART5,DefaultHandler
                  
   .weak      ISR_TIM6_DAC                  
   .thumb_set ISR_TIM6_DAC,DefaultHandler
               
   .weak      ISR_TIM7            
   .thumb_set ISR_TIM7,DefaultHandler
         
   .weak      ISR_DMA2_Stream0               
   .thumb_set ISR_DMA2_Stream0,DefaultHandler
               
   .weak      ISR_DMA2_Stream1               
   .thumb_set ISR_DMA2_Stream1,DefaultHandler
                  
   .weak      ISR_DMA2_Stream2               
   .thumb_set ISR_DMA2_Stream2,DefaultHandler
            
   .weak      ISR_DMA2_Stream3               
   .thumb_set ISR_DMA2_Stream3,DefaultHandler
            
   .weak      ISR_DMA2_Stream4               
   .thumb_set ISR_DMA2_Stream4,DefaultHandler
   
   .weak      ISR_DMA2_Stream4               
   .thumb_set ISR_DMA2_Stream4,DefaultHandler   
                           
   .weak      ISR_OTG_FS      
   .thumb_set ISR_OTG_FS,DefaultHandler
                     
   .weak      ISR_DMA2_Stream5               
   .thumb_set ISR_DMA2_Stream5,DefaultHandler
                  
   .weak      ISR_DMA2_Stream6               
   .thumb_set ISR_DMA2_Stream6,DefaultHandler
                  
   .weak      ISR_DMA2_Stream7               
   .thumb_set ISR_DMA2_Stream7,DefaultHandler
                  
   .weak      ISR_USART6      
   .thumb_set ISR_USART6,DefaultHandler
                        
   .weak      ISR_I2C3_EV   
   .thumb_set ISR_I2C3_EV,DefaultHandler
                        
   .weak      ISR_I2C3_ER   
   .thumb_set ISR_I2C3_ER,DefaultHandler
                        
   .weak      ISR_OTG_HS_EP1_OUT         
   .thumb_set ISR_OTG_HS_EP1_OUT,DefaultHandler
               
   .weak      ISR_OTG_HS_EP1_IN            
   .thumb_set ISR_OTG_HS_EP1_IN,DefaultHandler
               
   .weak      ISR_OTG_HS_WKUP         
   .thumb_set ISR_OTG_HS_WKUP,DefaultHandler
            
   .weak      ISR_OTG_HS      
   .thumb_set ISR_OTG_HS,DefaultHandler

   .weak      ISR_AES            
   .thumb_set ISR_AES,DefaultHandler

   .weak      ISR_RNG            
   .thumb_set ISR_RNG,DefaultHandler   

   .weak      ISR_FPU                  
   .thumb_set ISR_FPU,DefaultHandler

   .weak      ISR_UART7                  
   .thumb_set ISR_UART7,DefaultHandler

   .weak      ISR_UART8                  
   .thumb_set ISR_UART8,DefaultHandler   

   .weak      ISR_SPI4            
   .thumb_set ISR_SPI4,DefaultHandler
   
   .weak      ISR_SPI5            
   .thumb_set ISR_SPI5,DefaultHandler  

   .weak      ISR_SAI1            
   .thumb_set ISR_SAI1,DefaultHandler

   .weak      ISR_SAI2            
   .thumb_set ISR_SAI2,DefaultHandler
   
   .weak      ISR_QUADSPI            
   .thumb_set ISR_QUADSPI,DefaultHandler
 
   .weak      ISR_LPTIM1            
   .thumb_set ISR_LPTIM1,DefaultHandler

   .weak      ISR_SDMMC2            
   .thumb_set ISR_SDMMC2,DefaultHandler  
