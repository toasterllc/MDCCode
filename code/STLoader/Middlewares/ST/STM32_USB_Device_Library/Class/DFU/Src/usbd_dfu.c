/**
  ******************************************************************************
  * @file    usbd_dfu.c
  * @author  MCD Application Team
  * @brief   This file provides the DFU core functions.
  *
  * @verbatim
  *
  *          ===================================================================
  *                                DFU Class Driver Description
  *          ===================================================================
  *           This driver manages the DFU class V1.1 following the "Device Class Specification for
  *           Device Firmware Upgrade Version 1.1 Aug 5, 2004".
  *           This driver implements the following aspects of the specification:
  *             - Device descriptor management
  *             - Configuration descriptor management
  *             - Enumeration as DFU device (in DFU mode only)
  *             - Requests management (supporting ST DFU sub-protocol)
  *             - Memory operations management (Download/Upload/Erase/Detach/GetState/GetStatus)
  *             - DFU state machine implementation.
  *
  *           @note
  *            ST DFU sub-protocol is compliant with DFU protocol and use sub-requests to manage
  *            memory addressing, commands processing, specific memories operations (ie. Erase) ...
  *            As required by the DFU specification, only endpoint 0 is used in this application.
  *            Other endpoints and functions may be added to the application (ie. DFU ...)
  *
  *           These aspects may be enriched or modified for a specific user application.
  *
  *           This driver doesn't implement the following aspects of the specification
  *           (but it is possible to manage these features with some modifications on this driver):
  *             - Manifestation Tolerant mode
  *
  *  @endverbatim
  *
  ******************************************************************************
  * @attention
  *
  * <h2><center>&copy; Copyright (c) 2015 STMicroelectronics.
  * All rights reserved.</center></h2>
  *
  * This software component is licensed by ST under Ultimate Liberty license
  * SLA0044, the "License"; You may not use this file except in compliance with
  * the License. You may obtain a copy of the License at:
  *                      www.st.com/SLA0044
  *
  ******************************************************************************
  */

/* BSPDependencies
- "stm32xxxxx_{eval}{discovery}{nucleo_144}.c"
- "stm32xxxxx_{eval}{discovery}_io.c"
EndBSPDependencies */

/* Includes ------------------------------------------------------------------*/
#include "usbd_dfu.h"
#include "usbd_ctlreq.h"
#include <stdbool.h>


/** @addtogroup STM32_USB_DEVICE_LIBRARY
  * @{
  */


/** @defgroup USBD_DFU
  * @brief usbd core module
  * @{
  */

/** @defgroup USBD_DFU_Private_TypesDefinitions
  * @{
  */
/**
  * @}
  */


/** @defgroup USBD_DFU_Private_Defines
  * @{
  */

/**
  * @}
  */


/** @defgroup USBD_DFU_Private_Macros
  * @{
  */

/**
  * @}
  */


/** @defgroup USBD_DFU_Private_FunctionPrototypes
  * @{
  */

static uint8_t USBD_DFU_Init(USBD_HandleTypeDef *pdev, uint8_t cfgidx);
static uint8_t USBD_DFU_DeInit(USBD_HandleTypeDef *pdev, uint8_t cfgidx);
static uint8_t USBD_DFU_Setup(USBD_HandleTypeDef *pdev, USBD_SetupReqTypedef *req);
static uint8_t USBD_DFU_EP0_RxReady(USBD_HandleTypeDef *pdev);
static uint8_t USBD_DFU_EP0_TxReady(USBD_HandleTypeDef *pdev);
static uint8_t USBD_DFU_DataIn(USBD_HandleTypeDef *pdev, uint8_t epnum);
static uint8_t USBD_DFU_DataOut(USBD_HandleTypeDef *pdev, uint8_t epnum);
static uint8_t USBD_DFU_SOF(USBD_HandleTypeDef *pdev);

static uint8_t *USBD_DFU_GetCfgDesc(uint16_t *length);
static uint8_t *USBD_DFU_GetDeviceQualifierDesc(uint16_t *length);

#if (USBD_SUPPORT_USER_STRING_DESC == 1U)
static uint8_t *USBD_DFU_GetUsrStringDesc(USBD_HandleTypeDef *pdev,
                                          uint8_t index, uint16_t *length);
#endif

/**
  * @}
  */

/** @defgroup USBD_DFU_Private_Variables
  * @{
  */

USBD_ClassTypeDef USBD_DFU =
{
  USBD_DFU_Init,
  USBD_DFU_DeInit,
  USBD_DFU_Setup,
  USBD_DFU_EP0_TxReady,
  USBD_DFU_EP0_RxReady,
  USBD_DFU_DataIn,
  USBD_DFU_DataOut,
  USBD_DFU_SOF,
  NULL,
  NULL,
  USBD_DFU_GetCfgDesc,
  USBD_DFU_GetCfgDesc,
  USBD_DFU_GetCfgDesc,
  USBD_DFU_GetDeviceQualifierDesc,
#if (USBD_SUPPORT_USER_STRING_DESC == 1U)
  USBD_DFU_GetUsrStringDesc
#endif
};

#define BL_MAX_PACKET_SIZE      512

#define BL_EP_OUT_STM32     0x01
#define BL_EP_IN_STM32      0x81

#define BL_EP_OUT_ICE40     0x02
#define BL_EP_IN_ICE40      0x82

/* USB DFU device Configuration Descriptor */
#define USBD_DFU_CfgDescLen 55
__ALIGN_BEGIN static uint8_t USBD_DFU_CfgDesc[USBD_DFU_CfgDescLen] __ALIGN_END =
{
    // Configuration descriptor
    0x09,                                       // bLength: configuration descriptor length
    USB_DESC_TYPE_CONFIGURATION,                // bDescriptorType: configuration descriptor
    LOBYTE(USBD_DFU_CfgDescLen),           // wTotalLength: total descriptor length
    HIBYTE(USBD_DFU_CfgDescLen),
    0x02,                                       // bNumInterfaces: 2 interfaces
    0x01,                                       // bConfigurationValue: config 1
    0x00,                                       // iConfiguration: string descriptor index
    0x80,                                       // bmAttributes: bus powered
    0xFA,                                       // bMaxPower: 500 mA (2 mA units)
    
        // Interface descriptor: STM32 bootloader
        0x09,                                       // bLength: interface descriptor length
        USB_DESC_TYPE_INTERFACE,                    // bDescriptorType: interface descriptor
        0x00,                                       // bInterfaceNumber: Number of Interface
        0x00,                                       // bAlternateSetting: Alternate setting
        0x02,                                       // bNumEndpoints
        0xFF,                                       // bInterfaceClass: vendor specific
        0x00,                                       // bInterfaceSubClass
        0x00,                                       // nInterfaceProtocol
        0x00,                                       // iInterface: string descriptor index
        
            // Endpoint OUT Descriptor
            0x07,                                                       // bLength: Endpoint Descriptor size
            USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
            BL_EP_OUT_STM32,                                            // bEndpointAddress
            0x02,                                                       // bmAttributes: Bulk
            LOBYTE(BL_MAX_PACKET_SIZE), HIBYTE(BL_MAX_PACKET_SIZE),     // wMaxPacketSize
            0x00,                                                       // bInterval: ignore for Bulk transfer
            
            // Endpoint IN Descriptor
            0x07,                                                       // bLength: Endpoint Descriptor size
            USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
            BL_EP_IN_STM32,                                             // bEndpointAddress
            0x02,                                                       // bmAttributes: Bulk
            LOBYTE(BL_MAX_PACKET_SIZE), HIBYTE(BL_MAX_PACKET_SIZE),     // wMaxPacketSize
            0x00,                                                       // bInterval: ignore for Bulk transfer
        
        // Interface descriptor: ICE40 bootloader
        0x09,                                       // bLength: interface descriptor length
        USB_DESC_TYPE_INTERFACE,                    // bDescriptorType: interface descriptor
        0x01,                                       // bInterfaceNumber: Number of Interface
        0x00,                                       // bAlternateSetting: Alternate setting
        0x02,                                       // bNumEndpoints
        0xFF,                                       // bInterfaceClass: vendor specific
        0x00,                                       // bInterfaceSubClass
        0x00,                                       // nInterfaceProtocol
        0x00,                                       // iInterface: string descriptor index
        
            // Endpoint OUT Descriptor
            0x07,                                                       // bLength: Endpoint Descriptor size
            USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
            BL_EP_OUT_ICE40,                                            // bEndpointAddress
            0x02,                                                       // bmAttributes: Bulk
            LOBYTE(BL_MAX_PACKET_SIZE), HIBYTE(BL_MAX_PACKET_SIZE),     // wMaxPacketSize
            0x00,                                                       // bInterval: ignore for Bulk transfer
            
            // Endpoint IN Descriptor
            0x07,                                                       // bLength: Endpoint Descriptor size
            USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
            BL_EP_IN_ICE40,                                             // bEndpointAddress
            0x02,                                                       // bmAttributes: Bulk
            LOBYTE(BL_MAX_PACKET_SIZE), HIBYTE(BL_MAX_PACKET_SIZE),     // wMaxPacketSize
            0x00,                                                       // bInterval: ignore for Bulk transfer
};

/* USB Standard Device Descriptor */
__ALIGN_BEGIN static uint8_t USBD_DFU_DeviceQualifierDesc[USB_LEN_DEV_QUALIFIER_DESC] __ALIGN_END =
{
  USB_LEN_DEV_QUALIFIER_DESC,               // bLength
  USB_DESC_TYPE_DEVICE_QUALIFIER,           // bDescriptorType
  0x00, 0x02,                               // bcdUSB
  0x00,                                     // bDeviceClass
  0x00,                                     // bDeviceSubClass
  0x00,                                     // bDeviceProtocol
  0x40,                                     // bMaxPacketSize0
  0x01,                                     // bNumConfigurations
  0x00,                                     // bReserved
};

/**
  * @}
  */

/** @defgroup USBD_DFU_Private_Functions
  * @{
  */

/**
  * @brief  USBD_DFU_Init
  *         Initialize the DFU interface
  * @param  pdev: device instance
  * @param  cfgidx: Configuration index
  * @retval status
  */
static uint8_t USBD_DFU_Init(USBD_HandleTypeDef *pdev, uint8_t cfgidx)
{
    UNUSED(cfgidx);
    
    USBD_DFU_HandleTypeDef *hdfu;
    
    /* Allocate Audio structure */
    hdfu = USBD_malloc(sizeof(USBD_DFU_HandleTypeDef));
    
    if (hdfu == NULL)
    {
        pdev->pClassData = NULL;
        return (uint8_t)USBD_EMEM;
    }
    
    pdev->pClassData = (void *)hdfu;
    
    hdfu->alt_setting = 0U;
    hdfu->data_ptr = USBD_DFU_APP_DEFAULT_ADD;
    hdfu->wblock_num = 0U;
    hdfu->wlength = 0U;
    
    hdfu->manif_state = DFU_MANIFEST_COMPLETE;
    hdfu->dev_state = DFU_STATE_IDLE;
    
    hdfu->dev_status[0] = DFU_ERROR_NONE;
    hdfu->dev_status[1] = 0U;
    hdfu->dev_status[2] = 0U;
    hdfu->dev_status[3] = 0U;
    hdfu->dev_status[4] = DFU_STATE_IDLE;
    hdfu->dev_status[5] = 0U;
    
    // Open endpoints for STM32 interface
    {
        // OUT endpoint
        USBD_LL_OpenEP(pdev, BL_EP_OUT_STM32, USBD_EP_TYPE_BULK, BL_MAX_PACKET_SIZE);
        pdev->ep_out[BL_EP_OUT_STM32 & 0xFU].is_used = 1U;
        
        // IN endpoint
        USBD_LL_OpenEP(pdev, BL_EP_IN_STM32, USBD_EP_TYPE_BULK, BL_MAX_PACKET_SIZE);
        pdev->ep_in[BL_EP_IN_STM32 & 0xFU].is_used = 1U;
    }
    
    // Open endpoints for ICE40 interface
    {
        // OUT endpoint
        USBD_LL_OpenEP(pdev, BL_EP_OUT_ICE40, USBD_EP_TYPE_BULK, BL_MAX_PACKET_SIZE);
        pdev->ep_out[BL_EP_OUT_ICE40 & 0xFU].is_used = 1U;
        
        // IN endpoint
        USBD_LL_OpenEP(pdev, BL_EP_IN_ICE40, USBD_EP_TYPE_BULK, BL_MAX_PACKET_SIZE);
        pdev->ep_in[BL_EP_IN_ICE40 & 0xFU].is_used = 1U;
    }
    
    /* Initialize Hardware layer */
    if (((USBD_DFU_MediaTypeDef *)pdev->pUserData)->Init() != USBD_OK)
    {
        return (uint8_t)USBD_FAIL;
    }
    
    hdfu->STM32Loader.cmd = STM32LoaderCmd_None;
    hdfu->STM32Loader.state = 0;
    
    // FIXME: debug
    USBD_LL_PrepareReceive(pdev, BL_EP_OUT_STM32, (uint8_t*)&hdfu->STM32Loader.addr, sizeof(hdfu->STM32Loader.addr));
    
    // Prepare OUT endpoints to receive next packet
//    USBD_LL_PrepareReceive(pdev, BL_EP_OUT_STM32, (uint8_t*)&hdfu->STM32Loader.cmd, sizeof(hdfu->STM32Loader.cmd));
    // TODO: implement ice40 bootloader. we'll need a temporary buffer to store stuff while
//    USBD_LL_PrepareReceive(pdev, BL_EP_OUT_ICE40, hcdc->RxBuffer, BL_MAX_PACKET_SIZE);
    
    return (uint8_t)USBD_OK;
}






/**
  * @brief  USBD_DFU_Init
  *         De-Initialize the DFU layer
  * @param  pdev: device instance
  * @param  cfgidx: Configuration index
  * @retval status
  */
static uint8_t USBD_DFU_DeInit(USBD_HandleTypeDef *pdev, uint8_t cfgidx)
{
  UNUSED(cfgidx);
  USBD_DFU_HandleTypeDef *hdfu;

  if (pdev->pClassData == NULL)
  {
    return (uint8_t)USBD_EMEM;
  }

  hdfu = (USBD_DFU_HandleTypeDef *)pdev->pClassData;
  hdfu->wblock_num = 0U;
  hdfu->wlength = 0U;

  hdfu->dev_state = DFU_STATE_IDLE;
  hdfu->dev_status[0] = DFU_ERROR_NONE;
  hdfu->dev_status[4] = DFU_STATE_IDLE;

  /* DeInit  physical Interface components and Hardware Layer */
  ((USBD_DFU_MediaTypeDef *)pdev->pUserData)->DeInit();
  USBD_free(pdev->pClassData);
  pdev->pClassData = NULL;

  return (uint8_t)USBD_OK;
}

extern void setLed0(int on);
extern void setLed1(int on);
extern void setLed2(int on);
extern void setLed3(int on);
static void resetLEDs() {
    setLed0(0);
    setLed1(0);
    setLed2(0);
    setLed3(0);
}

/**
  * @brief  USBD_DFU_Setup
  *         Handle the DFU specific requests
  * @param  pdev: instance
  * @param  req: usb requests
  * @retval status
  */
static uint8_t USBD_DFU_Setup(USBD_HandleTypeDef *pdev, USBD_SetupReqTypedef *req)
{
  USBD_DFU_HandleTypeDef *hdfu = (USBD_DFU_HandleTypeDef *)pdev->pClassData;
  USBD_StatusTypeDef ret = USBD_OK;
  uint8_t *pbuf = NULL;
  uint16_t len = 0U;
  uint16_t status_info = 0U;
  uint8_t ep_addr = LOBYTE(req->wIndex);

  switch (req->bmRequest & USB_REQ_TYPE_MASK)
  {
  case USB_REQ_TYPE_CLASS:
    switch (req->bRequest)
    {
    default:
      USBD_CtlError(pdev, req);
      ret = USBD_FAIL;
      break;
    }
    break;

  case USB_REQ_TYPE_STANDARD:
    switch (req->bRequest)
    {
    case USB_REQ_GET_STATUS:
      if (pdev->dev_state == USBD_STATE_CONFIGURED)
      {
        (void)USBD_CtlSendData(pdev, (uint8_t *)&status_info, 2U);
      }
      else
      {
        USBD_CtlError(pdev, req);
        ret = USBD_FAIL;
      }
      break;

    case USB_REQ_GET_DESCRIPTOR:
      if ((req->wValue >> 8) == DFU_DESCRIPTOR_TYPE)
      {
        pbuf = USBD_DFU_CfgDesc + (9U * (USBD_DFU_MAX_ITF_NUM + 1U));
        len = MIN(USB_DFU_DESC_SIZ, req->wLength);
      }

      (void)USBD_CtlSendData(pdev, pbuf, len);
      break;

    case USB_REQ_GET_INTERFACE:
      if (pdev->dev_state == USBD_STATE_CONFIGURED)
      {
        (void)USBD_CtlSendData(pdev, (uint8_t *)hdfu->alt_setting, 1U);
      }
      else
      {
        USBD_CtlError(pdev, req);
        ret = USBD_FAIL;
      }
      break;

    case USB_REQ_SET_INTERFACE:
      if ((uint8_t)(req->wValue) < USBD_DFU_MAX_ITF_NUM)
      {
        if (pdev->dev_state == USBD_STATE_CONFIGURED)
        {
          hdfu->alt_setting = (uint8_t)(req->wValue);
        }
        else
        {
          USBD_CtlError(pdev, req);
          ret = USBD_FAIL;
        }
      }
      else
      {
        /* Call the error management function (command will be nacked */
        USBD_CtlError(pdev, req);
        ret = USBD_FAIL;
      }
      break;

    case USB_REQ_CLEAR_FEATURE:
      if (pdev->dev_state == USBD_STATE_CONFIGURED)
      {
        if (req->wValue == USB_FEATURE_EP_HALT)
        {
          if (ep_addr == BL_EP_OUT_STM32)
          {
            resetLEDs();
            USBD_LL_PrepareReceive(pdev, BL_EP_OUT_STM32, (uint8_t*)&hdfu->STM32Loader.addr, sizeof(hdfu->STM32Loader.addr));
          }
        }
      }
      else
      {
        USBD_CtlError(pdev, req);
        ret = USBD_FAIL;
      }
      break;

    default:
      USBD_CtlError(pdev, req);
      ret = USBD_FAIL;
      break;
    }
    break;

  default:
    USBD_CtlError(pdev, req);
    ret = USBD_FAIL;
    break;
  }

  return (uint8_t)ret;
}


/**
  * @brief  USBD_DFU_GetCfgDesc
  *         return configuration descriptor
  * @param  speed : current device speed
  * @param  length : pointer data length
  * @retval pointer to descriptor buffer
  */
static uint8_t *USBD_DFU_GetCfgDesc(uint16_t *length)
{
  *length = (uint16_t)sizeof(USBD_DFU_CfgDesc);

  return USBD_DFU_CfgDesc;
}


/**
  * @brief  USBD_DFU_EP0_RxReady
  *         handle EP0 Rx Ready event
  * @param  pdev: device instance
  * @retval status
  */
static uint8_t USBD_DFU_EP0_RxReady(USBD_HandleTypeDef *pdev)
{
  UNUSED(pdev);
  return (uint8_t)USBD_OK;
}
/**
  * @brief  USBD_DFU_EP0_TxReady
  *         handle EP0 TRx Ready event
  * @param  pdev: device instance
  * @retval status
  */
static uint8_t USBD_DFU_EP0_TxReady(USBD_HandleTypeDef *pdev)
{
  UNUSED(pdev);
  return (uint8_t)USBD_OK;
}
/**
  * @brief  USBD_DFU_SOF
  *         handle SOF event
  * @param  pdev: device instance
  * @retval status
  */
static uint8_t USBD_DFU_SOF(USBD_HandleTypeDef *pdev)
{
  UNUSED(pdev);

  return (uint8_t)USBD_OK;
}



static uint8_t USBD_DFU_DataIn(USBD_HandleTypeDef *pdev, uint8_t epnum)
{
  UNUSED(pdev);
  UNUSED(epnum);

  /* Only OUT data are processed */
  return (uint8_t)USBD_OK;
}

static uint32_t vectorTableAddr __attribute__((section(".noinit")));
static uint8_t USBD_DFU_DataOut(USBD_HandleTypeDef *pdev, uint8_t epnum)
{
    USBD_DFU_HandleTypeDef *hdfu = (USBD_DFU_HandleTypeDef *)pdev->pClassData;
    if (epnum == BL_EP_OUT_STM32) {
//        ledState = (hdfu->STM32Bootloader.address != 0);
//        USBD_LL_PrepareReceive(pdev, BL_EP_OUT_STM32, (uint8_t*)&hdfu->STM32Bootloader.address, sizeof(hdfu->STM32Bootloader.address));
        
        const uint16_t packetLen = (uint16_t)USBD_LL_GetRxDataSize(pdev, epnum);
        
        resetLEDs();
        switch (packetLen) {
        case 1: setLed0(1); break;
        case 2: setLed1(1); break;
        case 3: setLed2(1); break;
        case 4: setLed3(1); break;
        }
        
        if (packetLen != 4) {
            USBD_LL_StallEP(pdev, epnum);
//            USBD_CtlError(pdev, NULL);
            return USBD_FAIL;
        }
        
        USBD_LL_PrepareReceive(pdev, BL_EP_OUT_STM32, (uint8_t*)&hdfu->STM32Loader.addr, sizeof(hdfu->STM32Loader.addr));
        
        vectorTableAddr = hdfu->STM32Loader.addr;
        
//        // TODO: what happens if we get less bytes than we specified to USBD_LL_PrepareReceive?
//        const uint16_t packetLen = (uint16_t)USBD_LL_GetRxDataSize(pdev, epnum);
//        bool cmdDone = false;
//        switch (hdfu->STM32Loader.cmd) {
//        case STM32LoaderCmd_WriteData: {
//            switch (hdfu->STM32Loader.state) {
//            case 0:
//                USBD_LL_PrepareReceive(pdev, BL_EP_OUT_STM32, (uint8_t*)&hdfu->STM32Loader.addr, sizeof(hdfu->STM32Loader.addr));
//                break;
//            case 1:
//                USBD_LL_PrepareReceive(pdev, BL_EP_OUT_STM32, (uint8_t*)hdfu->STM32Loader.addr, BL_MAX_PACKET_SIZE);
//                break;
//            case 2:
//                cmdDone = true;
//                break;
//            }
//            break;
//        }
//        
//        case STM32LoaderCmd_Reset: {
//            switch (hdfu->STM32Loader.state) {
//            case 0:
//                USBD_LL_PrepareReceive(pdev, BL_EP_OUT_STM32, (uint8_t*)&hdfu->STM32Loader.addr, sizeof(hdfu->STM32Loader.addr));
//                break;
//            case 1:
//                // Stash the vector table address in a place that is accessible across resets
//                vectorTableAddr = hdfu->STM32Loader.addr;
//                // Perform software reset
//                NVIC_SystemReset();
//                break;
//            }
//            break;
//        }}
//        
//        hdfu->STM32Loader.state++;
//        
//        if (cmdDone) {
//            USBD_LL_PrepareReceive(pdev, BL_EP_OUT_STM32, (uint8_t*)&hdfu->STM32Loader.cmd, sizeof(hdfu->STM32Loader.cmd));
//            hdfu->STM32Loader.state = 0;
//        }
    }
    
    return (uint8_t)USBD_OK;
}




/**
* @brief  DeviceQualifierDescriptor
*         return Device Qualifier descriptor
* @param  length : pointer data length
* @retval pointer to descriptor buffer
*/
static uint8_t *USBD_DFU_GetDeviceQualifierDesc(uint16_t *length)
{
  *length = (uint16_t)sizeof(USBD_DFU_DeviceQualifierDesc);

  return USBD_DFU_DeviceQualifierDesc;
}

/**
  * @brief  USBD_DFU_GetUsrStringDesc
  *         Manages the transfer of memory interfaces string descriptors.
  * @param  speed : current device speed
  * @param  index: desciptor index
  * @param  length : pointer data length
  * @retval pointer to the descriptor table or NULL if the descriptor is not supported.
  */
#if (USBD_SUPPORT_USER_STRING_DESC == 1U)
static uint8_t *USBD_DFU_GetUsrStringDesc(USBD_HandleTypeDef *pdev, uint8_t index, uint16_t *length)
{
  static uint8_t USBD_StrDesc[255];
  USBD_DFU_MediaTypeDef *DfuInterface = (USBD_DFU_MediaTypeDef *)pdev->pUserData;

  /* Check if the requested string interface is supported */
  if (index <= (USBD_IDX_INTERFACE_STR + USBD_DFU_MAX_ITF_NUM))
  {
    USBD_GetString((uint8_t *)DfuInterface->pStrDesc, USBD_StrDesc, length);
    return USBD_StrDesc;
  }
  else
  {
    /* Not supported Interface Descriptor index */
    return NULL;
  }
}
#endif

/**
* @brief  USBD_MSC_RegisterStorage
* @param  fops: storage callback
* @retval status
*/
uint8_t USBD_DFU_RegisterMedia(USBD_HandleTypeDef *pdev,
                               USBD_DFU_MediaTypeDef *fops)
{
  if (fops == NULL)
  {
    return (uint8_t)USBD_FAIL;
  }

  pdev->pUserData = fops;

  return (uint8_t)USBD_OK;
}

/************************ (C) COPYRIGHT STMicroelectronics *****END OF FILE****/
