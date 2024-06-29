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
#include "GPIO.h"

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
extern "C" void SystemClock_Config(void);
/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* USER CODE END 0 */



/**
  * @brief System Clock Configuration
  * @retval None
  */
extern "C" void SystemClock_Config() {
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


// LEDs
using LED0 = GPIO::PortB::Pin<11, GPIO::Option::Output0>;
using LED1 = GPIO::PortB::Pin<13, GPIO::Option::Output0>;

using _USB_DM   = GPIO::PortB::Pin<14, GPIO::Option::Speed3, GPIO::Option::AltFn12>;
using _USB_DP   = GPIO::PortB::Pin<15, GPIO::Option::Speed3, GPIO::Option::AltFn12>;

// _OSC_IN / _OSC_OUT: used for providing external clock
// There's no alt function to configure here; we just need these to exist so that GPIO
// enables the clock for the relevent port (PortH)
using _OSC_IN   = GPIO::PortH::Pin<0>;
using _OSC_OUT  = GPIO::PortH::Pin<1>;



#warning TODO: update Abort to accept a domain / line, like we do with MSPApp?
extern "C"
[[noreturn]]
void abort() {
    Toastbox::IntState ints(false);
    
    for (bool x=true;; x=!x) {
        LED0::Write(x);
        LED1::Write(x);
        for (volatile uint32_t i=0; i<(uint32_t)500000; i++);
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

    GPIO::Init<
        LED0,
        LED1,

        _USB_DM,
        _USB_DP,

        _OSC_IN,
        _OSC_OUT
    >();
        
        __HAL_RCC_GPIOA_CLK_ENABLE();
        __HAL_RCC_GPIOB_CLK_ENABLE();
        __HAL_RCC_GPIOC_CLK_ENABLE();
        __HAL_RCC_GPIOD_CLK_ENABLE();
        __HAL_RCC_GPIOE_CLK_ENABLE();
        __HAL_RCC_GPIOF_CLK_ENABLE();
        __HAL_RCC_GPIOG_CLK_ENABLE();
        __HAL_RCC_GPIOH_CLK_ENABLE();
        __HAL_RCC_GPIOI_CLK_ENABLE();
        __HAL_RCC_SYSCFG_CLK_ENABLE();
        __HAL_RCC_OTGPHYC_CLK_ENABLE();

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();
  
  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */
  
  
  MX_FATFS_Init();
  
  MX_USB_DEVICE_Init();
  
  abort();
  
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
