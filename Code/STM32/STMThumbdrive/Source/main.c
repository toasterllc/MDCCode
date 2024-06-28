/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
  ******************************************************************************
  * @attention
  *
  * <h2><center>&copy; Copyright (c) 2024 STMicroelectronics.
  * All rights reserved.</center></h2>
  *
  * This software component is licensed by ST under BSD 3-Clause license,
  * the "License"; You may not use this file except in compliance with the
  * License. You may obtain a copy of the License at:
  *                        opensource.org/licenses/BSD-3-Clause
  *
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "fatfs.h"
#include "usb_device.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* USER CODE END 0 */



/**
  * @brief System Clock Configuration
  * @retval None
  */
static void _ClockInit() {
    // Configure the main internal regulator output voltage
    {
        __HAL_RCC_PWR_CLK_ENABLE();
        __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE3);
    }
    
    // Initialize RCC oscillators
    {
        RCC_OscInitTypeDef cfg = {};
        cfg.OscillatorType = RCC_OSCILLATORTYPE_HSE;
        cfg.HSEState = RCC_HSE_BYPASS;
        cfg.PLL.PLLState = RCC_PLL_ON;
        cfg.PLL.PLLSource = RCC_PLLSOURCE_HSE;
        cfg.PLL.PLLM = 8;
        cfg.PLL.PLLN = 128;
        cfg.PLL.PLLP = RCC_PLLP_DIV2;
        cfg.PLL.PLLQ = 2;
        
        HAL_StatusTypeDef hr = HAL_RCC_OscConfig(&cfg);
        assert(hr == HAL_OK);
    }
    
    // Initialize bus clocks for CPU, AHB, APB
    {
        RCC_ClkInitTypeDef cfg = {};
        cfg.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK|RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
        cfg.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
        cfg.AHBCLKDivider = RCC_SYSCLK_DIV1;
        cfg.APB1CLKDivider = RCC_HCLK_DIV4;
        cfg.APB2CLKDivider = RCC_HCLK_DIV2;
        
        HAL_StatusTypeDef hr = HAL_RCC_ClockConfig(&cfg, FLASH_LATENCY_6);
        assert(hr == HAL_OK);
    }
    
    {
        RCC_PeriphCLKInitTypeDef cfg = {};
        cfg.PeriphClockSelection = RCC_PERIPHCLK_I2C1|RCC_PERIPHCLK_CLK48;
        cfg.PLLSAI.PLLSAIN = 96;
        cfg.PLLSAI.PLLSAIQ = 2;
        cfg.PLLSAI.PLLSAIP = RCC_PLLSAIP_DIV4;
        cfg.PLLSAIDivQ = 1;
        cfg.I2c1ClockSelection = RCC_I2C1CLKSOURCE_PCLK1;
        cfg.Clk48ClockSelection = RCC_CLK48SOURCE_PLLSAIP;
        
        HAL_StatusTypeDef hr = HAL_RCCEx_PeriphCLKConfig(&cfg);
        assert(hr == HAL_OK);
    }
}



/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{
  /* USER CODE BEGIN 1 */

  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  void _ClockInit();
  _ClockInit();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_FATFS_Init();
  MX_USB_DEVICE_Init();
  /* USER CODE BEGIN 2 */

  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
  }
  /* USER CODE END 3 */
}

/**
  * @brief GPIO Initialization Function
  * @param None
  * @retval None
  */
static void MX_GPIO_Init(void)
{

  /* GPIO Ports Clock Enable */
  __HAL_RCC_GPIOB_CLK_ENABLE();

}

/* USER CODE BEGIN 4 */

/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
  }
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
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */

/************************ (C) COPYRIGHT STMicroelectronics *****END OF FILE****/
