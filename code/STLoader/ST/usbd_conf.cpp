#include "usbd_conf.h"
#include "stm32f7xx.h"
#include "usbd_def.h"
#include "usbd_core.h"
#include "SystemClock.h"
#include "abort.h"

PCD_HandleTypeDef hpcd_USB_OTG_HS;

USBD_StatusTypeDef USBD_Get_USB_Status(HAL_StatusTypeDef hal_status);

static void SystemClockConfig_Resume();

void HAL_PCD_MspInit(PCD_HandleTypeDef* pcdHandle)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};
  if(pcdHandle->Instance==USB_OTG_HS)
  {
    __HAL_RCC_GPIOB_CLK_ENABLE();
    
    // USB_OTG_HS_DP: PB15
    // USB_OTG_HS_DM: PB14
    GPIO_InitStruct.Pin = GPIO_PIN_14|GPIO_PIN_15;
    GPIO_InitStruct.Mode = GPIO_MODE_AF_PP;
    GPIO_InitStruct.Pull = GPIO_NOPULL;
    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_VERY_HIGH;
    GPIO_InitStruct.Alternate = GPIO_AF12_OTG_HS_FS;
    HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

    // Peripheral clock enable
    __HAL_RCC_USB_OTG_HS_CLK_ENABLE();
    __HAL_RCC_USB_OTG_HS_ULPI_CLK_ENABLE();
    // Required to enable USB PHY clock. Otherwise USB_HS_PHYCInit() will fail with HAL_TIMEOUT.
    // It appears to be a bug that the STM tools doesn't generate this for us.
    __HAL_RCC_OTGPHYC_CLK_ENABLE();

    // Peripheral interrupt init
    HAL_NVIC_SetPriority(OTG_HS_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(OTG_HS_IRQn);
  }
}

void HAL_PCD_MspDeInit(PCD_HandleTypeDef* pcdHandle)
{
  if(pcdHandle->Instance==USB_OTG_HS)
  {
    // Disable Peripheral clock
    __HAL_RCC_USB_OTG_HS_CLK_DISABLE();
    __HAL_RCC_USB_OTG_HS_ULPI_CLK_DISABLE();

    // USB_OTG_HS GPIO Configuration
    // USB_OTG_HS_DP: PB15
    // USB_OTG_HS_DM: PB14
    HAL_GPIO_DeInit(GPIOB, GPIO_PIN_14|GPIO_PIN_15);

    // Peripheral interrupt Deinit
    HAL_NVIC_DisableIRQ(OTG_HS_IRQn);
  }
}

void HAL_PCD_SetupStageCallback(PCD_HandleTypeDef *hpcd)
{
  USBD_LL_SetupStage((USBD_HandleTypeDef*)hpcd->pData, (uint8_t *)hpcd->Setup);
}

void HAL_PCD_DataOutStageCallback(PCD_HandleTypeDef *hpcd, uint8_t epnum)
{
  USBD_LL_DataOutStage((USBD_HandleTypeDef*)hpcd->pData, epnum, hpcd->OUT_ep[epnum].xfer_buff);
}

void HAL_PCD_DataInStageCallback(PCD_HandleTypeDef *hpcd, uint8_t epnum)
{
  USBD_LL_DataInStage((USBD_HandleTypeDef*)hpcd->pData, epnum, hpcd->IN_ep[epnum].xfer_buff);
}

void HAL_PCD_SOFCallback(PCD_HandleTypeDef *hpcd)
{
  USBD_LL_SOF((USBD_HandleTypeDef*)hpcd->pData);
}

void HAL_PCD_ResetCallback(PCD_HandleTypeDef *hpcd)
{
  USBD_SpeedTypeDef speed = USBD_SPEED_FULL;

  if ( hpcd->Init.speed == PCD_SPEED_HIGH)
  {
    speed = USBD_SPEED_HIGH;
  }
  else if ( hpcd->Init.speed == PCD_SPEED_FULL)
  {
    speed = USBD_SPEED_FULL;
  }
  else
  {
    abort();
  }
    // Set Speed
  USBD_LL_SetSpeed((USBD_HandleTypeDef*)hpcd->pData, speed);

  // Reset Device
  USBD_LL_Reset((USBD_HandleTypeDef*)hpcd->pData);
}

void HAL_PCD_SuspendCallback(PCD_HandleTypeDef *hpcd)
{
  // Inform USB library that core enters in suspend Mode
  USBD_LL_Suspend((USBD_HandleTypeDef*)hpcd->pData);
  __HAL_PCD_GATE_PHYCLOCK(hpcd);
  // Enter in STOP mode
  if (hpcd->Init.low_power_enable)
  {
    // Set SLEEPDEEP bit and SleepOnExit of Cortex System Control Register
    SCB->SCR |= (uint32_t)((uint32_t)(SCB_SCR_SLEEPDEEP_Msk | SCB_SCR_SLEEPONEXIT_Msk));
  }
}

void HAL_PCD_ResumeCallback(PCD_HandleTypeDef *hpcd)
{
  USBD_LL_Resume((USBD_HandleTypeDef*)hpcd->pData);
}

void HAL_PCD_ISOOUTIncompleteCallback(PCD_HandleTypeDef *hpcd, uint8_t epnum)
{
  USBD_LL_IsoOUTIncomplete((USBD_HandleTypeDef*)hpcd->pData, epnum);
}

void HAL_PCD_ISOINIncompleteCallback(PCD_HandleTypeDef *hpcd, uint8_t epnum)
{
  USBD_LL_IsoINIncomplete((USBD_HandleTypeDef*)hpcd->pData, epnum);
}

void HAL_PCD_ConnectCallback(PCD_HandleTypeDef *hpcd)
{
  USBD_LL_DevConnected((USBD_HandleTypeDef*)hpcd->pData);
}

void HAL_PCD_DisconnectCallback(PCD_HandleTypeDef *hpcd)
{
  USBD_LL_DevDisconnected((USBD_HandleTypeDef*)hpcd->pData);
}

// Initializes the low level portion of the device driver.
USBD_StatusTypeDef USBD_LL_Init(USBD_HandleTypeDef *pdev)
{
  // Init USB Ip
  if (pdev->id == DEVICE_HS) {
      // Link the driver to the stack
      hpcd_USB_OTG_HS.pData = pdev;
      pdev->pData = &hpcd_USB_OTG_HS;

      hpcd_USB_OTG_HS.Instance = USB_OTG_HS;
      hpcd_USB_OTG_HS.Init.dev_endpoints = 9;
      hpcd_USB_OTG_HS.Init.dma_enable = DISABLE;
      hpcd_USB_OTG_HS.Init.phy_itface = USB_OTG_HS_EMBEDDED_PHY;
      hpcd_USB_OTG_HS.Init.Sof_enable = DISABLE;
      hpcd_USB_OTG_HS.Init.low_power_enable = DISABLE;
      hpcd_USB_OTG_HS.Init.lpm_enable = DISABLE;
      hpcd_USB_OTG_HS.Init.vbus_sensing_enable = DISABLE;
      hpcd_USB_OTG_HS.Init.use_dedicated_ep1 = DISABLE;
      hpcd_USB_OTG_HS.Init.use_external_vbus = DISABLE;
      if (HAL_PCD_Init(&hpcd_USB_OTG_HS) != HAL_OK)
      {
        abort();
      }

      HAL_PCDEx_SetRxFiFo(&hpcd_USB_OTG_HS, 0x200);
      HAL_PCDEx_SetTxFiFo(&hpcd_USB_OTG_HS, 0, 0x80);
      HAL_PCDEx_SetTxFiFo(&hpcd_USB_OTG_HS, 1, 0x174);
  }
  return USBD_OK;
}

// De-Initializes the low level portion of the device driver.
USBD_StatusTypeDef USBD_LL_DeInit(USBD_HandleTypeDef *pdev)
{
  HAL_StatusTypeDef hal_status = HAL_OK;
  USBD_StatusTypeDef usb_status = USBD_OK;

  hal_status = HAL_PCD_DeInit((PCD_HandleTypeDef*)pdev->pData);

  usb_status =  USBD_Get_USB_Status(hal_status);

  return usb_status;
}

// Starts the low level portion of the device driver.
USBD_StatusTypeDef USBD_LL_Start(USBD_HandleTypeDef *pdev)
{
  HAL_StatusTypeDef hal_status = HAL_OK;
  USBD_StatusTypeDef usb_status = USBD_OK;

  hal_status = HAL_PCD_Start((PCD_HandleTypeDef*)pdev->pData);

  usb_status =  USBD_Get_USB_Status(hal_status);

  return usb_status;
}

// Stops the low level portion of the device driver.
USBD_StatusTypeDef USBD_LL_Stop(USBD_HandleTypeDef *pdev)
{
  HAL_StatusTypeDef hal_status = HAL_OK;
  USBD_StatusTypeDef usb_status = USBD_OK;

  hal_status = HAL_PCD_Stop((PCD_HandleTypeDef*)pdev->pData);

  usb_status =  USBD_Get_USB_Status(hal_status);

  return usb_status;
}

// Opens an endpoint of the low level driver.
USBD_StatusTypeDef USBD_LL_OpenEP(USBD_HandleTypeDef *pdev, uint8_t ep_addr, uint8_t ep_type, uint16_t ep_mps)
{
  HAL_StatusTypeDef hal_status = HAL_OK;
  USBD_StatusTypeDef usb_status = USBD_OK;

  hal_status = HAL_PCD_EP_Open((PCD_HandleTypeDef*)pdev->pData, ep_addr, ep_mps, ep_type);

  usb_status =  USBD_Get_USB_Status(hal_status);

  return usb_status;
}

// Closes an endpoint of the low level driver.
USBD_StatusTypeDef USBD_LL_CloseEP(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  HAL_StatusTypeDef hal_status = HAL_OK;
  USBD_StatusTypeDef usb_status = USBD_OK;

  hal_status = HAL_PCD_EP_Close((PCD_HandleTypeDef*)pdev->pData, ep_addr);

  usb_status =  USBD_Get_USB_Status(hal_status);

  return usb_status;
}

// Flushes an endpoint of the Low Level Driver.
USBD_StatusTypeDef USBD_LL_FlushEP(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  HAL_StatusTypeDef hal_status = HAL_OK;
  USBD_StatusTypeDef usb_status = USBD_OK;

  hal_status = HAL_PCD_EP_Flush((PCD_HandleTypeDef*)pdev->pData, ep_addr);

  usb_status =  USBD_Get_USB_Status(hal_status);

  return usb_status;
}

// Sets a Stall condition on an endpoint of the Low Level Driver.
USBD_StatusTypeDef USBD_LL_StallEP(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  HAL_StatusTypeDef hal_status = HAL_OK;
  USBD_StatusTypeDef usb_status = USBD_OK;

  hal_status = HAL_PCD_EP_SetStall((PCD_HandleTypeDef*)pdev->pData, ep_addr);

  usb_status =  USBD_Get_USB_Status(hal_status);

  return usb_status;
}

// Clears a Stall condition on an endpoint of the Low Level Driver.
USBD_StatusTypeDef USBD_LL_ClearStallEP(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  HAL_StatusTypeDef hal_status = HAL_OK;
  USBD_StatusTypeDef usb_status = USBD_OK;

  hal_status = HAL_PCD_EP_ClrStall((PCD_HandleTypeDef*)pdev->pData, ep_addr);

  usb_status =  USBD_Get_USB_Status(hal_status);

  return usb_status;
}

// Returns Stall condition.
uint8_t USBD_LL_IsStallEP(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  PCD_HandleTypeDef *hpcd = (PCD_HandleTypeDef*) pdev->pData;

  if((ep_addr & 0x80) == 0x80)
  {
    return hpcd->IN_ep[ep_addr & 0x7F].is_stall;
  }
  else
  {
    return hpcd->OUT_ep[ep_addr & 0x7F].is_stall;
  }
}

// Assigns a USB address to the device.
USBD_StatusTypeDef USBD_LL_SetUSBAddress(USBD_HandleTypeDef *pdev, uint8_t dev_addr)
{
  HAL_StatusTypeDef hal_status = HAL_OK;
  USBD_StatusTypeDef usb_status = USBD_OK;

  hal_status = HAL_PCD_SetAddress((PCD_HandleTypeDef*)pdev->pData, dev_addr);

  usb_status =  USBD_Get_USB_Status(hal_status);

  return usb_status;
}

// Transmits data over an endpoint.
USBD_StatusTypeDef USBD_LL_Transmit(USBD_HandleTypeDef *pdev, uint8_t ep_addr, uint8_t *pbuf, uint32_t size)
{
  HAL_StatusTypeDef hal_status = HAL_OK;
  USBD_StatusTypeDef usb_status = USBD_OK;

  hal_status = HAL_PCD_EP_Transmit((PCD_HandleTypeDef*)pdev->pData, ep_addr, pbuf, size);

  usb_status =  USBD_Get_USB_Status(hal_status);

  return usb_status;
}

// Prepares an endpoint for reception.
USBD_StatusTypeDef USBD_LL_PrepareReceive(USBD_HandleTypeDef *pdev, uint8_t ep_addr, uint8_t *pbuf, uint32_t size)
{
  HAL_StatusTypeDef hal_status = HAL_OK;
  USBD_StatusTypeDef usb_status = USBD_OK;

  hal_status = HAL_PCD_EP_Receive((PCD_HandleTypeDef*)pdev->pData, ep_addr, pbuf, size);

  usb_status =  USBD_Get_USB_Status(hal_status);

  return usb_status;
}

// Returns the last transfered packet size.
uint32_t USBD_LL_GetRxDataSize(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  return HAL_PCD_EP_GetRxCount((PCD_HandleTypeDef*) pdev->pData, ep_addr);
}

// Send LPM message to user layer
void HAL_PCDEx_LPM_Callback(PCD_HandleTypeDef *hpcd, PCD_LPM_MsgTypeDef msg)
{
  switch (msg)
  {
  case PCD_LPM_L0_ACTIVE:
    if (hpcd->Init.low_power_enable)
    {
      SystemClockConfig_Resume();

      // Reset SLEEPDEEP bit of Cortex System Control Register
      SCB->SCR &= (uint32_t)~((uint32_t)(SCB_SCR_SLEEPDEEP_Msk | SCB_SCR_SLEEPONEXIT_Msk));
    }
    __HAL_PCD_UNGATE_PHYCLOCK(hpcd);
    USBD_LL_Resume((USBD_HandleTypeDef*)hpcd->pData);
    break;

  case PCD_LPM_L1_ACTIVE:
    __HAL_PCD_GATE_PHYCLOCK(hpcd);
    USBD_LL_Suspend((USBD_HandleTypeDef*)hpcd->pData);

    // Enter in STOP mode
    if (hpcd->Init.low_power_enable)
    {
      // Set SLEEPDEEP bit and SleepOnExit of Cortex System Control Register
      SCB->SCR |= (uint32_t)((uint32_t)(SCB_SCR_SLEEPDEEP_Msk | SCB_SCR_SLEEPONEXIT_Msk));
    }
    break;
  }
}

// Configures system clock after wake-up from USB resume callBack:
// enable HSI, PLL and select PLL as system clock source.
static void SystemClockConfig_Resume() {
    SystemClock::Init();
}

// Retuns the USB status depending on the HAL status:
USBD_StatusTypeDef USBD_Get_USB_Status(HAL_StatusTypeDef hal_status) {
    switch (hal_status) {
    case HAL_OK:    return USBD_OK;
    case HAL_BUSY:  return USBD_BUSY;
    default:        return USBD_FAIL;
    }
}
