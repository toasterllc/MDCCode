#include "usbd_core.h"
#include "stm32f7xx.h"
#include "stm32f7xx_hal.h"

USBD_StatusTypeDef USBD_Get_USB_Status(HAL_StatusTypeDef hal_status);

static void SystemClockConfig_Resume();

void HAL_PCD_MspInit(PCD_HandleTypeDef* pcdHandle)
{
//  GPIO_InitTypeDef GPIO_InitStruct = {0};
  if(pcdHandle->Instance==USB_OTG_HS)
  {
    // GPIO is configured by System.h
//    __HAL_RCC_GPIOB_CLK_ENABLE();
//    
//    // USB_OTG_HS_DP: PB15
//    // USB_OTG_HS_DM: PB14
//    GPIO_InitStruct.Pin = GPIO_PIN_14|GPIO_PIN_15;
//    GPIO_InitStruct.Mode = GPIO_MODE_AF_PP;
//    GPIO_InitStruct.Pull = GPIO_NOPULL;
//    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_VERY_HIGH;
//    GPIO_InitStruct.Alternate = GPIO_AF12_OTG_HS_FS;
//    HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

    // Peripheral clock enable
    __HAL_RCC_USB_OTG_HS_CLK_ENABLE();
    __HAL_RCC_USB_OTG_HS_ULPI_CLK_ENABLE();
    // Required to enable USB PHY clock. Otherwise USB_HS_PHYCInit() will fail with HAL_TIMEOUT.
    // It appears to be a bug that the STM tools doesn't generate this for us.
    __HAL_RCC_OTGPHYC_CLK_ENABLE();

    // Peripheral interrupt init
    constexpr uint32_t InterruptPriority = 1; // Should be >0 so that SysTick can still preempt
    HAL_NVIC_SetPriority(OTG_HS_IRQn, InterruptPriority, 0);
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
    Assert(false);
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

// Starts the low level portion of the device driver.
USBD_StatusTypeDef USBD_LL_Start(USBD_HandleTypeDef *pdev)
{
  return USBD_Get_USB_Status(HAL_PCD_Start((PCD_HandleTypeDef*)pdev->pData));
}

// Stops the low level portion of the device driver.
USBD_StatusTypeDef USBD_LL_Stop(USBD_HandleTypeDef *pdev)
{
  return USBD_Get_USB_Status(HAL_PCD_Stop((PCD_HandleTypeDef*)pdev->pData));
}

// Opens an endpoint of the low level driver.
USBD_StatusTypeDef USBD_LL_OpenEP(USBD_HandleTypeDef *pdev, uint8_t ep_addr, uint8_t ep_type, uint16_t ep_mps)
{
  return USBD_Get_USB_Status(HAL_PCD_EP_Open((PCD_HandleTypeDef*)pdev->pData, ep_addr, ep_mps, ep_type));
}

// Closes an endpoint of the low level driver.
USBD_StatusTypeDef USBD_LL_CloseEP(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  return USBD_Get_USB_Status(HAL_PCD_EP_Close((PCD_HandleTypeDef*)pdev->pData, ep_addr));
}

// Flushes an endpoint of the Low Level Driver.
USBD_StatusTypeDef USBD_LL_FlushEP(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  return USBD_Get_USB_Status(HAL_PCD_EP_Flush((PCD_HandleTypeDef*)pdev->pData, ep_addr));
}

// Sets a Stall condition on an endpoint of the Low Level Driver.
USBD_StatusTypeDef USBD_LL_StallEP(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  return USBD_Get_USB_Status(HAL_PCD_EP_SetStall((PCD_HandleTypeDef*)pdev->pData, ep_addr));
}

// Clears a Stall condition on an endpoint of the Low Level Driver.
USBD_StatusTypeDef USBD_LL_ClearStallEP(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  return USBD_Get_USB_Status(HAL_PCD_EP_ClrStall((PCD_HandleTypeDef*)pdev->pData, ep_addr));
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
  return USBD_Get_USB_Status(HAL_PCD_SetAddress((PCD_HandleTypeDef*)pdev->pData, dev_addr));
}

// Transmits data over an endpoint.
USBD_StatusTypeDef USBD_LL_Transmit(USBD_HandleTypeDef *pdev, uint8_t ep_addr, uint8_t *pbuf, uint32_t size)
{
  return USBD_Get_USB_Status(HAL_PCD_EP_Transmit((PCD_HandleTypeDef*)pdev->pData, ep_addr, pbuf, size));
}

USBD_StatusTypeDef USBD_LL_TransmitZeroLen(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  return USBD_Get_USB_Status(HAL_PCD_EP_TransmitZeroLen((PCD_HandleTypeDef*)pdev->pData, ep_addr));
}

// Prepares an endpoint for reception.
USBD_StatusTypeDef USBD_LL_PrepareReceive(USBD_HandleTypeDef *pdev, uint8_t ep_addr, uint8_t *pbuf, uint32_t size)
{
  return USBD_Get_USB_Status(HAL_PCD_EP_Receive((PCD_HandleTypeDef*)pdev->pData, ep_addr, pbuf, size));
}

// Prepares an endpoint for reception.
USBD_StatusTypeDef USBD_LL_PrepareReceiveZeroLen(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  return USBD_Get_USB_Status(HAL_PCD_EP_ReceiveZeroLen((PCD_HandleTypeDef*)pdev->pData, ep_addr));
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
    // DKeck: unimplemented
    Assert(false);
}

// Retuns the USB status depending on the HAL status:
USBD_StatusTypeDef USBD_Get_USB_Status(HAL_StatusTypeDef hal_status) {
    switch (hal_status) {
    case HAL_OK:    return USBD_OK;
    case HAL_BUSY:  return USBD_BUSY;
    default:        return USBD_FAIL;
    }
}


// Initializes the device stack and load the class driver
USBD_StatusTypeDef USBD_Init(USBD_HandleTypeDef* pdev, USBD_DescriptorsTypeDef* pdesc, uint8_t id)
{
  // Check whether the USB Host handle is valid
  if (pdev == NULL) {
    return USBD_FAIL;
  }

  // Unlink previous class
  pdev->pClass = NULL;
  pdev->pConfDesc = NULL;

  // Assign USBD Descriptors
  pdev->pDesc = pdesc;

  // Set Device initial State
  pdev->dev_state = USBD_STATE_DEFAULT;
  pdev->id = id;

  return USBD_OK;
}

// Re-Initialize th device library
USBD_StatusTypeDef USBD_DeInit(USBD_HandleTypeDef* pdev)
{
  USBD_StatusTypeDef ret;

  // Set Default State
  pdev->dev_state = USBD_STATE_DEFAULT;

  // Free Class Resources
  if (pdev->pClass != NULL)
  {
    pdev->pClass->DeInit(pdev, (uint8_t)pdev->dev_config);
  }

  pdev->pConfDesc = NULL;

  // Stop the low level driver
  ret = USBD_LL_Stop(pdev);

  if (ret != USBD_OK)
  {
    return ret;
  }

  return ret;
}

// Link class driver to Device Core.
USBD_StatusTypeDef USBD_RegisterClass(USBD_HandleTypeDef* pdev, const USBD_ClassTypeDef* pclass)
{
  uint16_t len = 0U;

  if (pclass == NULL) {
    return USBD_FAIL;
  }

  // link the class to the USB Device handle
  pdev->pClass = pclass;

  // Get Device Configuration Descriptor
#ifdef USE_USB_FS
  pdev->pConfDesc = (void* )pdev->pClass->GetFSConfigDescriptor(pdev, &len);
#else // USE_USB_HS
  pdev->pConfDesc = (void* )pdev->pClass->GetHSConfigDescriptor(pdev, &len);
#endif // USE_USB_FS


  return USBD_OK;
}

// Start the USB Device Core.
USBD_StatusTypeDef USBD_Start(USBD_HandleTypeDef* pdev)
{
  // Start the low level driver
  return USBD_LL_Start(pdev);
}

// Stop the USB Device Core.
USBD_StatusTypeDef USBD_Stop(USBD_HandleTypeDef* pdev)
{
  USBD_StatusTypeDef ret;

  // Free Class Resources
  if (pdev->pClass != NULL)
  {
    pdev->pClass->DeInit(pdev, (uint8_t)pdev->dev_config);
  }

  if (pdev->pConfDesc != NULL)
  {
    pdev->pConfDesc = NULL;
  }

  // Stop the low level driver
  ret = USBD_LL_Stop(pdev);

  return ret;
}

// Launch test mode process
USBD_StatusTypeDef USBD_RunTestMode(USBD_HandleTypeDef* pdev)
{
  return USBD_OK;
}

// Configure device and start the interface
USBD_StatusTypeDef USBD_SetClassConfig(USBD_HandleTypeDef* pdev, uint8_t cfgidx)
{
  USBD_StatusTypeDef ret = USBD_FAIL;

  if (pdev->pClass != NULL)
  {
    // Set configuration and Start the Class
    ret = (USBD_StatusTypeDef)pdev->pClass->Init(pdev, cfgidx);
  }

  return ret;
}

// Clear current configuration
USBD_StatusTypeDef USBD_ClrClassConfig(USBD_HandleTypeDef* pdev, uint8_t cfgidx)
{
  // Clear configuration and De-initialize the Class process
  if (pdev->pClass != NULL)
  {
    pdev->pClass->DeInit(pdev, cfgidx);
  }

  return USBD_OK;
}


// Handle the setup stage
USBD_StatusTypeDef USBD_LL_SetupStage(USBD_HandleTypeDef* pdev, uint8_t* psetup)
{
  USBD_StatusTypeDef ret;

  USBD_ParseSetupRequest(&pdev->request, psetup);

  pdev->ep0_state = USBD_EP0_SETUP;

  pdev->ep0_data_len = pdev->request.wLength;

  switch (pdev->request.bmRequest & 0x1FU)
  {
    case USB_REQ_RECIPIENT_DEVICE:
      ret = USBD_StdDevReq(pdev, &pdev->request);
      break;

    case USB_REQ_RECIPIENT_INTERFACE:
      ret = USBD_StdItfReq(pdev, &pdev->request);
      break;

    case USB_REQ_RECIPIENT_ENDPOINT:
      ret = USBD_StdEPReq(pdev, &pdev->request);
      break;

    default:
      ret = USBD_LL_StallEP(pdev, (pdev->request.bmRequest & 0x80U));
      break;
  }

  return ret;
}

// Handle data OUT stage
USBD_StatusTypeDef USBD_LL_DataOutStage(USBD_HandleTypeDef* pdev,
                                        uint8_t epnum, uint8_t* pdata)
{
  USBD_EndpointTypeDef* pep;
  USBD_StatusTypeDef ret;
  
  if (epnum == 0U)
  {
    pep = &pdev->ep_out[0];

    if (pdev->ep0_state == USBD_EP0_DATA_OUT)
    {
      if (pep->rem_length > pep->maxpacket)
      {
        pep->rem_length -= pep->maxpacket;

        (void)USBD_CtlContinueRx(pdev, pdata, MIN(pep->rem_length, pep->maxpacket));
      }
      else
      {
        if ((pdev->pClass->EP0_RxReady != NULL) && (pdev->dev_state == USBD_STATE_CONFIGURED))
        {
          pdev->pClass->EP0_RxReady(pdev);
        }
        else
        {
          // DKeck: only send status if we're not calling the client's callback.
          // DKeck: if we are calling the client's callback, let the it handle sending the status.
          (void)USBD_CtlSendStatus(pdev);
        }
      }
    }
  }
  else if ((pdev->pClass->DataOut != NULL) &&
           (pdev->dev_state == USBD_STATE_CONFIGURED))
  {
    ret = (USBD_StatusTypeDef)pdev->pClass->DataOut(pdev, epnum);

    if (ret != USBD_OK)
    {
      return ret;
    }
  }
  else
  {
    // should never be in this condition
    return USBD_FAIL;
  }

  return USBD_OK;
}

// Handle data in stage
USBD_StatusTypeDef USBD_LL_DataInStage(USBD_HandleTypeDef* pdev,
                                       uint8_t epnum, uint8_t* pdata)
{
  USBD_EndpointTypeDef* pep;
  USBD_StatusTypeDef ret;

  if (epnum == 0U)
  {
    pep = &pdev->ep_in[0];

    if (pdev->ep0_state == USBD_EP0_DATA_IN)
    {
      if (pep->rem_length > pep->maxpacket)
      {
        pep->rem_length -= pep->maxpacket;

        (void)USBD_CtlContinueSendData(pdev, pdata, pep->rem_length);

        // Prepare endpoint for premature end of transfer
       (void)USBD_LL_PrepareReceiveZeroLen(pdev, 0U);
      }
      else
      {
        // last packet is MPS multiple, so send ZLP packet
        if ((pep->maxpacket == pep->rem_length) &&
            (pep->total_length >= pep->maxpacket) &&
            (pep->total_length < pdev->ep0_data_len))
        {
          (void)USBD_CtlContinueSendData(pdev, NULL, 0U);
          pdev->ep0_data_len = 0U;

          // Prepare endpoint for premature end of transfer
          (void)USBD_LL_PrepareReceiveZeroLen(pdev, 0U);
        }
        else
        {
          if ((pdev->pClass->EP0_TxSent != NULL) &&
              (pdev->dev_state == USBD_STATE_CONFIGURED))
          {
            pdev->pClass->EP0_TxSent(pdev);
          }
          (void)USBD_LL_StallEP(pdev, 0x80U);
          (void)USBD_CtlReceiveStatus(pdev);
        }
      }
    }

    if (pdev->dev_test_mode == 1U)
    {
      (void)USBD_RunTestMode(pdev);
      pdev->dev_test_mode = 0U;
    }
  }
  else if ((pdev->pClass->DataIn != NULL) &&
           (pdev->dev_state == USBD_STATE_CONFIGURED))
  {
    ret = (USBD_StatusTypeDef)pdev->pClass->DataIn(pdev, epnum);

    if (ret != USBD_OK)
    {
      return ret;
    }
  }
  else
  {
    // should never be in this condition
    return USBD_FAIL;
  }

  return USBD_OK;
}

// Handle Reset event
USBD_StatusTypeDef USBD_LL_Reset(USBD_HandleTypeDef* pdev)
{
  // Upon Reset call user call back
  pdev->dev_state = USBD_STATE_DEFAULT;
  pdev->ep0_state = USBD_EP0_IDLE;
  pdev->dev_config = 0U;
  pdev->dev_remote_wakeup = 0U;

  if (pdev->pClass != NULL)
  {
    pdev->pClass->DeInit(pdev, (uint8_t)pdev->dev_config);
  }

    // Open EP0 OUT
  (void)USBD_LL_OpenEP(pdev, 0x00U, USBD_EP_TYPE_CTRL, USB_MAX_EP0_SIZE);
  pdev->ep_out[0x00U & 0xFU].is_used = 1U;

  pdev->ep_out[0].maxpacket = USB_MAX_EP0_SIZE;

  // Open EP0 IN
  (void)USBD_LL_OpenEP(pdev, 0x80U, USBD_EP_TYPE_CTRL, USB_MAX_EP0_SIZE);
  pdev->ep_in[0x80U & 0xFU].is_used = 1U;

  pdev->ep_in[0].maxpacket = USB_MAX_EP0_SIZE;

  return USBD_OK;
}

USBD_StatusTypeDef USBD_LL_SetSpeed(USBD_HandleTypeDef* pdev,
                                    USBD_SpeedTypeDef speed)
{
  pdev->dev_speed = speed;

  return USBD_OK;
}

// Handle Suspend event
USBD_StatusTypeDef USBD_LL_Suspend(USBD_HandleTypeDef* pdev)
{
  pdev->dev_old_state = pdev->dev_state;
  pdev->dev_state = USBD_STATE_SUSPENDED;

  if (pdev->pClass != NULL)
  {
    pdev->pClass->Suspend(pdev);
  }

  return USBD_OK;
}

// Handle Resume event
USBD_StatusTypeDef USBD_LL_Resume(USBD_HandleTypeDef* pdev)
{
  if (pdev->dev_state == USBD_STATE_SUSPENDED)
  {
    pdev->dev_state = pdev->dev_old_state;
  }

  if (pdev->pClass != NULL)
  {
    pdev->pClass->Resume(pdev);
  }

  return USBD_OK;
}

// Handle SOF event
USBD_StatusTypeDef USBD_LL_SOF(USBD_HandleTypeDef* pdev)
{
  if (pdev->dev_state == USBD_STATE_CONFIGURED)
  {
    if (pdev->pClass->SOF != NULL)
    {
      pdev->pClass->SOF(pdev);
    }
  }

  return USBD_OK;
}

// Handle iso in incomplete event
USBD_StatusTypeDef USBD_LL_IsoINIncomplete(USBD_HandleTypeDef* pdev, uint8_t epnum)
{
  return USBD_OK;
}

// Handle iso out incomplete event
USBD_StatusTypeDef USBD_LL_IsoOUTIncomplete(USBD_HandleTypeDef* pdev, uint8_t epnum)
{
  return USBD_OK;
}

// Handle device connection event
USBD_StatusTypeDef USBD_LL_DevConnected(USBD_HandleTypeDef* pdev)
{
  return USBD_OK;
}

// Handle device disconnection event
USBD_StatusTypeDef USBD_LL_DevDisconnected(USBD_HandleTypeDef* pdev)
{
  // Free Class Resources
  pdev->dev_state = USBD_STATE_DEFAULT;

  if (pdev->pClass != NULL)
  {
    pdev->pClass->DeInit(pdev, (uint8_t)pdev->dev_config);
  }

  return USBD_OK;
}
