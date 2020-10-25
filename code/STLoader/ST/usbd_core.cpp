#include "usbd_core.h"

// Initializes the device stack and load the class driver
USBD_StatusTypeDef USBD_Init(USBD_HandleTypeDef* pdev, USBD_DescriptorsTypeDef* pdesc, uint8_t id, void* ctx)
{
  USBD_StatusTypeDef ret;

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
  pdev->pCtx = ctx;

  // Initialize low level driver
  ret = USBD_LL_Init(pdev);

  return ret;
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
  pdev->pCtx = NULL;

  // Stop the low level driver
  ret = USBD_LL_Stop(pdev);

  if (ret != USBD_OK)
  {
    return ret;
  }

  // Initialize low level driver
  ret = USBD_LL_DeInit(pdev);

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
        (void)USBD_CtlSendStatus(pdev);
      }
    }
    else
    {
#if 0
      if (pdev->ep0_state == USBD_EP0_STATUS_OUT)
      {
        // STATUS PHASE completed, update ep0_state to idle
        pdev->ep0_state = USBD_EP0_IDLE;
        (void)USBD_LL_StallEP(pdev, 0U);
      }
#endif
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
       (void)USBD_LL_PrepareReceive(pdev, 0U, NULL, 0U);
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
          (void)USBD_LL_PrepareReceive(pdev, 0U, NULL, 0U);
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
    else
    {
#if 0
      if ((pdev->ep0_state == USBD_EP0_STATUS_IN) ||
          (pdev->ep0_state == USBD_EP0_IDLE))
      {
        (void)USBD_LL_StallEP(pdev, 0x80U);
      }
#endif
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

  return USBD_OK;
}

// Handle Resume event
USBD_StatusTypeDef USBD_LL_Resume(USBD_HandleTypeDef* pdev)
{
  if (pdev->dev_state == USBD_STATE_SUSPENDED)
  {
    pdev->dev_state = pdev->dev_old_state;
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
