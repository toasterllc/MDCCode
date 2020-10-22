#include "usbd_dfu.h"
#include <stdbool.h>
#include "usbd_ctlreq.h"
#include "Event.h"

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

Channel<USBDataOutEvent, 3> USBDataOutChannel;

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

#define MAX_PACKET_SIZE             512

#define ST_EPADDR_CMD_OUT           0x01    // OUT endpoint
#define ST_EPADDR_CMD_IN            0x81    // IN endpoint (high bit 1 = IN)
#define ST_EPADDR_DATA_OUT          0x02    // OUT endpoint

#define EPNUM(addr)                 (addr & 0xF)

/* USB DFU device Configuration Descriptor */
#define USBD_DFU_CfgDescLen 39
__ALIGN_BEGIN static uint8_t USBD_DFU_CfgDesc[USBD_DFU_CfgDescLen] __ALIGN_END =
{
    // Configuration descriptor
    0x09,                                       // bLength: configuration descriptor length
    USB_DESC_TYPE_CONFIGURATION,                // bDescriptorType: configuration descriptor
    LOBYTE(USBD_DFU_CfgDescLen),                // wTotalLength: total descriptor length
    HIBYTE(USBD_DFU_CfgDescLen),
    0x02,                                       // bNumInterfaces: 2 interfaces
    0x01,                                       // bConfigurationValue: config 1
    0x00,                                       // iConfiguration: string descriptor index
    0x80,                                       // bmAttributes: bus powered
    0xFA,                                       // bMaxPower: 500 mA (2 mA units)
    
        // Interface descriptor: ST bootloader
        0x09,                                       // bLength: interface descriptor length
        USB_DESC_TYPE_INTERFACE,                    // bDescriptorType: interface descriptor
        0x00,                                       // bInterfaceNumber: Number of Interface
        0x00,                                       // bAlternateSetting: Alternate setting
        0x03,                                       // bNumEndpoints
        0xFF,                                       // bInterfaceClass: vendor specific
        0x00,                                       // bInterfaceSubClass
        0x00,                                       // nInterfaceProtocol
        0x00,                                       // iInterface: string descriptor index
        
            // CMD_OUT endpoint
            0x07,                                                       // bLength: Endpoint Descriptor size
            USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
            ST_EPADDR_CMD_OUT,                                          // bEndpointAddress
            0x02,                                                       // bmAttributes: Bulk
            LOBYTE(MAX_PACKET_SIZE), HIBYTE(MAX_PACKET_SIZE),           // wMaxPacketSize
            0x00,                                                       // bInterval: ignore for Bulk transfer
            
            // CMD_IN endpoint
            0x07,                                                       // bLength: Endpoint Descriptor size
            USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
            ST_EPADDR_CMD_IN,                                           // bEndpointAddress
            0x02,                                                       // bmAttributes: Bulk
            LOBYTE(MAX_PACKET_SIZE), HIBYTE(MAX_PACKET_SIZE),           // wMaxPacketSize
            0x00,                                                       // bInterval: ignore for Bulk transfer
            
            // DATA_OUT endpoint
            0x07,                                                       // bLength: Endpoint Descriptor size
            USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
            ST_EPADDR_DATA_OUT,                                         // bEndpointAddress
            0x02,                                                       // bmAttributes: Bulk
            LOBYTE(MAX_PACKET_SIZE), HIBYTE(MAX_PACKET_SIZE),           // wMaxPacketSize
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
    hdfu = (USBD_DFU_HandleTypeDef*)USBD_malloc(sizeof(USBD_DFU_HandleTypeDef));
    
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
    
    // Open endpoints for ST bootloader interface
    {
        // CMD_OUT endpoint
        USBD_LL_OpenEP(pdev, ST_EPADDR_CMD_OUT, USBD_EP_TYPE_BULK, MAX_PACKET_SIZE);
        pdev->ep_out[EPNUM(ST_EPADDR_CMD_OUT)].is_used = 1U;
        
        // CMD_IN endpoint
        USBD_LL_OpenEP(pdev, ST_EPADDR_CMD_IN, USBD_EP_TYPE_BULK, MAX_PACKET_SIZE);
        pdev->ep_in[EPNUM(ST_EPADDR_CMD_IN)].is_used = 1U;
        
        // DATA_OUT endpoint
        USBD_LL_OpenEP(pdev, ST_EPADDR_DATA_OUT, USBD_EP_TYPE_BULK, MAX_PACKET_SIZE);
        pdev->ep_out[EPNUM(ST_EPADDR_DATA_OUT)].is_used = 1U;
    }
    
    /* Initialize Hardware layer */
    if (((USBD_DFU_MediaTypeDef *)pdev->pUserData)->Init() != USBD_OK)
    {
        return (uint8_t)USBD_FAIL;
    }
    
    USBD_LL_PrepareReceive(pdev, ST_EPADDR_CMD_OUT, (uint8_t*)&hdfu->stDataOutBuf, sizeof(hdfu->stDataOutBuf));
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

/**
  * @brief  USBD_DFU_Setup
  *         Handle the DFU specific requests
  * @param  pdev: instance
  * @param  req: usb requests
  * @retval status
  */
static uint8_t USBD_DFU_Setup(USBD_HandleTypeDef *pdev, USBD_SetupReqTypedef *req) {
    USBD_CtlError(pdev, req);
    return USBD_FAIL;
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

static uint8_t USBD_DFU_DataIn(USBD_HandleTypeDef *pdev, uint8_t epnum) {
    return (uint8_t)USBD_OK;
}

static uint8_t USBD_DFU_DataOut(USBD_HandleTypeDef *pdev, uint8_t epnum) {
    USBD_DFU_HandleTypeDef* hdfu = (USBD_DFU_HandleTypeDef*)pdev->pClassData;
    const size_t dataLen = USBD_LL_GetRxDataSize(pdev, epnum);
    
    USBDataOutChannel.writeTry(USBDataOutEvent{
        .endpoint = epnum,
        .data = hdfu->stDataOutBuf,
        .dataLen = dataLen,
    });
    
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
