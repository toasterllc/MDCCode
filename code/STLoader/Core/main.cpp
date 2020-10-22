#include <stdbool.h>
#include <algorithm>
#include "Event.h"
#include "Assert.h"
#include "usb_device.h"
#include "usbd_core.h"
#include "usbd_dfu.h"

extern void Error_Handler();
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_QUADSPI_Init(void);

QSPI_HandleTypeDef hqspi;

// TODO: these is declared in 2 places. cleanup!
#define MAX_PACKET_SIZE             512
#define ST_EPADDR_CMD_OUT           0x01    // OUT endpoint
#define ST_EPADDR_CMD_IN            0x81    // IN endpoint (high bit 1 = IN)
#define ST_EPADDR_DATA_OUT          0x02    // OUT endpoint
#define EPNUM(addr)                 (addr & 0xF)



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

static uintptr_t dataAddr = 0; // TODO: figure out where to put this
static void handleEvent_USBDataOut(const USBDataOutEvent& ev) {
    extern USBD_HandleTypeDef hUsbDeviceHS; // TODO: find where to put this
    
    switch (ev.endpoint) {
    
    // CMD_OUT endpoint:
    //   Handle the supplied command
    case EPNUM(ST_EPADDR_CMD_OUT): {
        STLoaderCmd cmd;
        // Verify that we received at least the command op
        Assert(ev.dataLen >= sizeof(cmd.op)); // TODO: handle errors
        Assert(ev.dataLen < sizeof(cmd)); // TODO: handle errors
        memcpy(&cmd, ev.data, std::min(sizeof(cmd), ev.dataLen));
        
        const size_t argLen = ev.dataLen-sizeof(cmd.op);
        switch (cmd.op) {
        // Set LED command:
        case STLoaderCmd::Op::LEDSet: {
            // Verify that we got the right argument size
            Assert(argLen == sizeof(cmd.arg.ledSet)); // TODO: handle errors
            extern void led0Set(bool on);
            extern void led1Set(bool on);
            extern void led2Set(bool on);
            extern void led3Set(bool on);
            
            switch (cmd.arg.ledSet.idx) {
            case 0: led0Set(cmd.arg.ledSet.on); break;
            case 1: led1Set(cmd.arg.ledSet.on); break;
            case 2: led2Set(cmd.arg.ledSet.on); break;
            case 3: led3Set(cmd.arg.ledSet.on); break;
            }
            
            break;
        }
        
        // Write data command:
        //   Stash the address we're writing to in `dataAddr`,
        //   Prepare the DATA_OUT endpoint for writing at that address
        case STLoaderCmd::Op::WriteData: {
            // Verify that we got the right argument size
            Assert(argLen == sizeof(cmd.arg.writeData)); // TODO: handle errors
            dataAddr = cmd.arg.writeData.addr;
            USBD_LL_PrepareReceive(&hUsbDeviceHS, ST_EPADDR_DATA_OUT, (uint8_t*)dataAddr, MAX_PACKET_SIZE);
            break;
        }
        
        // Reset command:
        //   Stash the vector table address for access after we reset,
        //   Perform a software reset
        case STLoaderCmd::Op::Reset: {
            // Verify we got the right argument size
            Assert(argLen == sizeof(cmd.arg.reset)); // TODO: handle errors
            extern uintptr_t AppEntryPointAddr;
            AppEntryPointAddr = cmd.arg.reset.entryPointAddr;
            // Perform software reset
            HAL_NVIC_SystemReset();
            break;
        }
        
        // Bad command
        default: {
            break;
        }}
        // Prepare to receive another command
        USBD_DFU_HandleTypeDef* hdfu = (USBD_DFU_HandleTypeDef*)hUsbDeviceHS.pClassData; // TODO: cleanup
        USBD_LL_PrepareReceive(&hUsbDeviceHS, ST_EPADDR_CMD_OUT, (uint8_t*)&hdfu->stDataOutBuf, sizeof(hdfu->stDataOutBuf));
        break;
    }
    
    // DATA_OUT endpoint:
    //   Update the address that we're writing to,
    //   Prepare ourself to receive more data
    case EPNUM(ST_EPADDR_DATA_OUT): {
        dataAddr += ev.dataLen;
        // Only prepare for more data if this packet was the maximum size.
        // Otherwise, this packet is the last packet (USB 2 spec 5.8.3:
        //   "A bulk transfer is complete when the endpoint ... Transfers a
        //   packet with a payload size less than wMaxPacketSize or
        //   transfers a zero-length packet".)
        if (ev.dataLen == MAX_PACKET_SIZE) {
            USBD_LL_PrepareReceive(&hUsbDeviceHS, ST_EPADDR_DATA_OUT, (uint8_t*)dataAddr, MAX_PACKET_SIZE);
        }
        break;
    }}
}

int main() {
    // Reset of all peripherals, Initializes the Flash interface and the Systick
    HAL_Init();
    
    // Configure the system clock
    SystemClock_Config();
    
    // Initialize all configured peripherals
    MX_GPIO_Init();
    MX_QUADSPI_Init();
    MX_USB_DEVICE_Init();
    
    // Event loop
    for (;;) {
        // Dequeue outstanding events
        Channels::SelectStart();
        if (auto x = USBDataOutChannel.read(Channels::Select)) {
            handleEvent_USBDataOut(*x);
        
        } else {
            // No events, go to sleep
            Channels::SelectWait();
        }
    }
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};
  RCC_PeriphCLKInitTypeDef PeriphClkInitStruct = {0};

  /** Configure the main internal regulator output voltage
  */
  __HAL_RCC_PWR_CLK_ENABLE();
  __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE3);
  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE;
  RCC_OscInitStruct.HSEState = RCC_HSE_BYPASS;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSE;
  RCC_OscInitStruct.PLL.PLLM = 12;
  RCC_OscInitStruct.PLL.PLLN = 128;
  RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV2;
  RCC_OscInitStruct.PLL.PLLQ = 2;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }
  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV4;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV2;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_6) != HAL_OK)
  {
    Error_Handler();
  }
  PeriphClkInitStruct.PeriphClockSelection = RCC_PERIPHCLK_CLK48;
  PeriphClkInitStruct.PLLSAI.PLLSAIN = 96;
  PeriphClkInitStruct.PLLSAI.PLLSAIQ = 2;
  PeriphClkInitStruct.PLLSAI.PLLSAIP = RCC_PLLSAIP_DIV4;
  PeriphClkInitStruct.PLLSAIDivQ = 1;
  PeriphClkInitStruct.Clk48ClockSelection = RCC_CLK48SOURCE_PLLSAIP;
  if (HAL_RCCEx_PeriphCLKConfig(&PeriphClkInitStruct) != HAL_OK)
  {
    Error_Handler();
  }
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
  hqspi.Instance = QUADSPI;
  hqspi.Init.ClockPrescaler = 5; // HCLK=128MHz -> QSPI clock = HCLK/(Prescalar+1) = 128/(7+1) = 21.3 MHz
  hqspi.Init.FifoThreshold = 1;
  hqspi.Init.SampleShifting = QSPI_SAMPLE_SHIFTING_NONE;
  hqspi.Init.FlashSize = 1;
  hqspi.Init.ChipSelectHighTime = QSPI_CS_HIGH_TIME_1_CYCLE;
  hqspi.Init.ClockMode = QSPI_CLOCK_MODE_0;
  hqspi.Init.FlashID = QSPI_FLASH_ID_1;
  hqspi.Init.DualFlash = QSPI_DUALFLASH_DISABLE;
  if (HAL_QSPI_Init(&hqspi) != HAL_OK)
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

#ifdef  USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line number,
     tex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */

/************************ (C) COPYRIGHT STMicroelectronics *****END OF FILE****/
