#include "usbd_ioreq.h"

// Send data on the ctl pipe
USBD_StatusTypeDef USBD_CtlSendData(USBD_HandleTypeDef *pdev,
                                    uint8_t *pbuf, uint32_t len)
{
  // Set EP0 State
  pdev->ep0_state = USBD_EP0_DATA_IN;
  pdev->ep_in[0].total_length = len;
  pdev->ep_in[0].rem_length = len;

  // Start the transfer
  (void)USBD_LL_Transmit(pdev, 0U, pbuf, len);

  return USBD_OK;
}

// Continue sending data on the ctl pipe
USBD_StatusTypeDef USBD_CtlContinueSendData(USBD_HandleTypeDef *pdev, uint8_t *pbuf, uint32_t len)
{
  // Start the next transfer
  (void)USBD_LL_Transmit(pdev, 0U, pbuf, len);

  return USBD_OK;
}

// Receive data on the ctl pipe
USBD_StatusTypeDef USBD_CtlPrepareRx(USBD_HandleTypeDef *pdev, uint8_t *pbuf, uint32_t len)
{
  // Set EP0 State
  pdev->ep0_state = USBD_EP0_DATA_OUT;
  pdev->ep_out[0].total_length = len;
  pdev->ep_out[0].rem_length = len;

  // Start the transfer
  (void)USBD_LL_PrepareReceive(pdev, 0U, pbuf, len);

  return USBD_OK;
}

// Continue receive data on the ctl pipe
USBD_StatusTypeDef USBD_CtlContinueRx(USBD_HandleTypeDef *pdev, uint8_t *pbuf, uint32_t len)
{
  (void)USBD_LL_PrepareReceive(pdev, 0U, pbuf, len);

  return USBD_OK;
}

// Send zero length packet on the ctl pipe
USBD_StatusTypeDef USBD_CtlSendStatus(USBD_HandleTypeDef *pdev)
{
  // Set EP0 State
  pdev->ep0_state = USBD_EP0_STATUS_IN;

  // Start the transfer
  (void)USBD_LL_TransmitZeroLen(pdev, 0U);

  return USBD_OK;
}

// Receive zero length packet on the ctl pipe
USBD_StatusTypeDef USBD_CtlReceiveStatus(USBD_HandleTypeDef *pdev)
{
  // Set EP0 State
  pdev->ep0_state = USBD_EP0_STATUS_OUT;

  // Start the transfer
  (void)USBD_LL_PrepareReceiveZeroLen(pdev, 0U);

  return USBD_OK;
}

// Returns the received data length
uint32_t USBD_GetRxCount(USBD_HandleTypeDef *pdev, uint8_t ep_addr)
{
  return USBD_LL_GetRxDataSize(pdev, ep_addr);
}
