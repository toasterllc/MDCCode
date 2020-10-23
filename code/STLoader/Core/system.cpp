#include <stdbool.h>
#include <algorithm>
#include "assert.h"
#include "usbd_core.h"
#include "USB.h"
#include "STLoaderTypes.h"
#include "SystemClock.h"

class System {
    void run() {
        // Reset peripherals, initialize flash interface, initialize Systick
        HAL_Init();
        
        // Configure the system clock
        SystemClock::Init();
        
        __HAL_RCC_GPIOH_CLK_ENABLE(); 
        __HAL_RCC_GPIOB_CLK_ENABLE(); // QSPI, QSPI
        __HAL_RCC_GPIOC_CLK_ENABLE(); // QSPI
        __HAL_RCC_GPIOE_CLK_ENABLE(); // LEDs
        
        // Initialize all configured peripherals
        MX_GPIO_Init();
        MX_QUADSPI_Init();
        usb.init();
        
        // Event loop
        for (;;) {
            // Dequeue outstanding events
            ChannelSelect::Start();
            if (auto x = usb.cmdOutChannel.readSelect()) {
                handleUSBCmd(*x);
            
            } else if (auto x = usb.dataOutChannel.readSelect()) {
                handleUSBData(*x);
            
            } else {
                // No events, go to sleep
                ChannelSelect::Wait();
            }
        }
    }
    
private:
    void _handleUSBCmd(const USB::CmdOutEvent& ev) {
        STLoaderCmd cmd;
        assert(ev.dataLen == sizeof(cmd)); // TODO: handle errors
        memcpy(&cmd, ev.data, ev.dataLen);
        switch (cmd.op) {
        // Get status
        case STLoaderCmd::Op::GetStatus: {
            usb.sendCmdIn(&_status, sizeof(_status));
            break;
        }
        
        // Write data
        //   Prepare the DATA_OUT endpoint for writing at the given address+length
        case STLoaderCmd::Op::WriteData: {
            _status = STLoaderStatus::Writing;
            void*const addr = (void*)cmd.arg.writeData.addr;
            // Verify that `addr` is in the allowed RAM range
            extern uint8_t _sram_app[];
            extern uint8_t _eram_app[];
            assert(addr >= _sram_app); // TODO: error handling
            assert(addr < _eram_app); // TODO: error handling
            const size_t len = (uintptr_t)_eram_app-(uintptr_t)addr;
            usb.recvDataOut((void*)cmd.arg.writeData.addr, len);
            break;
        }
        
        // Reset
        //   Stash the entry point address for access after we reset,
        //   Perform a software reset
        case STLoaderCmd::Op::Reset: {
            extern uintptr_t AppEntryPointAddr;
            AppEntryPointAddr = cmd.arg.reset.entryPointAddr;
            // Perform software reset
            HAL_NVIC_SystemReset();
            break;
        }
        
        // Set LED
        case STLoaderCmd::Op::LEDSet: {
            switch (cmd.arg.ledSet.idx) {
            case 0: led0Set(cmd.arg.ledSet.on); break;
            case 1: led1Set(cmd.arg.ledSet.on); break;
            case 2: led2Set(cmd.arg.ledSet.on); break;
            case 3: led3Set(cmd.arg.ledSet.on); break;
            }
            
            break;
        }
        
        // Bad command
        default: {
            break;
        }}
        
        // Prepare to receive another command
        usb.recvCmdOut(); // TODO: handle errors
    }
    
    void _handleUSBData(const USB::DataOutEvent& ev) {
        // We're done writing
        _status = STLoaderStatus::Idle;
    }
    
    USB _usb;
    QSPI_HandleTypeDef _qspi;
    STLoaderStatus _status = STLoaderStatus::Idle;
    
    GPIO<GPIOE, STM_LED0_Pin> led0;
    GPIO<GPIOE, STM_LED1_Pin> led1;
    GPIO<GPIOB, STM_LED2_Pin> led2;
    GPIO<GPIOB, STM_LED3_Pin> led3;
};

static System Sys;

extern void Error_Handler();
static void MX_GPIO_Init(void);
static void MX_QUADSPI_Init(void);

#define STM_LED0_Pin            GPIO_PIN_12
#define STM_LED0_GPIO_Port      GPIOE
#define STM_LED1_Pin            GPIO_PIN_15
#define STM_LED1_GPIO_Port      GPIOE
#define STM_LED2_Pin            GPIO_PIN_10
#define STM_LED2_GPIO_Port      GPIOB
#define STM_LED3_Pin            GPIO_PIN_11
#define STM_LED3_GPIO_Port      GPIOB

void led0Set(bool on) {
    HAL_GPIO_WritePin(GPIOE, STM_LED0_Pin, (on ? GPIO_PIN_SET : GPIO_PIN_RESET));
}

void led1Set(bool on) {
    HAL_GPIO_WritePin(GPIOE, STM_LED1_Pin, (on ? GPIO_PIN_SET : GPIO_PIN_RESET));
}

void led2Set(bool on) {
    HAL_GPIO_WritePin(GPIOB, STM_LED2_Pin, (on ? GPIO_PIN_SET : GPIO_PIN_RESET));
}

void led3Set(bool on) {
    HAL_GPIO_WritePin(GPIOB, STM_LED3_Pin, (on ? GPIO_PIN_SET : GPIO_PIN_RESET));
}

int main() {
    Sys.run();
}

/**
  * @brief GPIO Initialization Function
  * @param None
  * @retval None
  */
static void MX_GPIO_Init(void)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};

  /* GPIO Ports Clock Enable */
  __HAL_RCC_GPIOH_CLK_ENABLE();
  __HAL_RCC_GPIOE_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();
  __HAL_RCC_GPIOC_CLK_ENABLE();

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOE, STM_LED0_Pin|STM_LED1_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOB, STM_LED2_Pin|STM_LED3_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pins : STM_LED0_Pin STM_LED1_Pin */
  GPIO_InitStruct.Pin = STM_LED0_Pin|STM_LED1_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOE, &GPIO_InitStruct);

  /*Configure GPIO pins : STM_LED2_Pin STM_LED3_Pin */
  GPIO_InitStruct.Pin = STM_LED2_Pin|STM_LED3_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

}

/**
  * @brief QUADSPI Initialization Function
  * @param None
  * @retval None
  */
static void MX_QUADSPI_Init(void)
{

  /* USER CODE BEGIN QUADSPI_Init 0 */

  /* USER CODE END QUADSPI_Init 0 */

  /* USER CODE BEGIN QUADSPI_Init 1 */

  /* USER CODE END QUADSPI_Init 1 */
  /* QUADSPI parameter configuration*/
  qspi.Instance = QUADSPI;
  qspi.Init.ClockPrescaler = 5; // HCLK=128MHz -> QSPI clock = HCLK/(Prescalar+1) = 128/(7+1) = 21.3 MHz
  qspi.Init.FifoThreshold = 1;
  qspi.Init.SampleShifting = QSPI_SAMPLE_SHIFTING_NONE;
  qspi.Init.FlashSize = 1;
  qspi.Init.ChipSelectHighTime = QSPI_CS_HIGH_TIME_1_CYCLE;
  qspi.Init.ClockMode = QSPI_CLOCK_MODE_0;
  qspi.Init.FlashID = QSPI_FLASH_ID_1;
  qspi.Init.DualFlash = QSPI_DUALFLASH_DISABLE;
  if (HAL_QSPI_Init(&qspi) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN QUADSPI_Init 2 */

  /* USER CODE END QUADSPI_Init 2 */

}

/* USER CODE BEGIN 4 */

/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler()
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  /* USER CODE END Error_Handler_Debug */
}

/************************ (C) COPYRIGHT STMicroelectronics *****END OF FILE****/
