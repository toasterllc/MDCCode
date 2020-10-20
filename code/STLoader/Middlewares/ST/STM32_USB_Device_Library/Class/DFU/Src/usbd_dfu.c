#include "usbd_dfu.h"
#include "usbd_ctlreq.h"
#include <stdbool.h>

//extern void setLed0(int on);
//extern void setLed1(int on);
//extern void setLed2(int on);
//extern void setLed3(int on);
//static void resetLEDs() {
//    setLed0(0);
//    setLed1(0);
//    setLed2(0);
//    setLed3(0);
//}

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

#define MAX_PACKET_SIZE             512

#define STM32_ENDPOINT_CMD_OUT      0x01    // OUT endpoint
#define STM32_ENDPOINT_CMD_IN       0x81    // IN endpoint
//#define STM32_ENDPOINT_DATA_OUT     0x02    // OUT endpoint

/* USB DFU device Configuration Descriptor */
#define USBD_DFU_CfgDescLen 32
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
        
            // CMD_OUT endpoint
            0x07,                                                       // bLength: Endpoint Descriptor size
            USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
            STM32_ENDPOINT_CMD_OUT,                                     // bEndpointAddress
            0x02,                                                       // bmAttributes: Bulk
            LOBYTE(MAX_PACKET_SIZE), HIBYTE(MAX_PACKET_SIZE),           // wMaxPacketSize
            0x00,                                                       // bInterval: ignore for Bulk transfer
            
            // CMD_IN endpoint
            0x07,                                                       // bLength: Endpoint Descriptor size
            USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
            STM32_ENDPOINT_CMD_IN,                                      // bEndpointAddress
            0x02,                                                       // bmAttributes: Bulk
            LOBYTE(MAX_PACKET_SIZE), HIBYTE(MAX_PACKET_SIZE),           // wMaxPacketSize
            0x00,                                                       // bInterval: ignore for Bulk transfer
            
//            // DATA_OUT endpoint
//            0x07,                                                       // bLength: Endpoint Descriptor size
//            USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
//            STM32_ENDPOINT_DATA_OUT,                                    // bEndpointAddress
//            0x02,                                                       // bmAttributes: Bulk
//            LOBYTE(MAX_PACKET_SIZE), HIBYTE(MAX_PACKET_SIZE),           // wMaxPacketSize
//            0x00,                                                       // bInterval: ignore for Bulk transfer
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

static uint8_t randomDataBuf[] = "But the other reason why the Flex buds are an important product is, well, Android. Instead of using Apple's proprietary Lightning connector for charging, as many Beats headphones have since the acquisition, the Flex have a USB-C port. Beats' Android app has already been updated to support them. These moves show that as Apple continues putting a greater emphasis on audio products - with the new HomePod mini and long-rumored premium headphones expected to launch soon - Beats is realizing it needs to stand independently from Apple's ecosystem if the brand wants to continue its enormous success. $50 for decent-sounding wireless earbuds with W1 chips for Apple device integration, and USB-C charging and a nice-looking Android app for better outside-the-Apple-universe appeal. A product like this is exactly why Apple is keeping the Beats brand around.";

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
        // CMD_OUT endpoint
        USBD_LL_OpenEP(pdev, STM32_ENDPOINT_CMD_OUT, USBD_EP_TYPE_BULK, MAX_PACKET_SIZE);
        pdev->ep_out[STM32_ENDPOINT_CMD_OUT & 0xFU].is_used = 1U;
        
        // CMD_IN endpoint
        USBD_LL_OpenEP(pdev, STM32_ENDPOINT_CMD_IN, USBD_EP_TYPE_BULK, MAX_PACKET_SIZE);
        pdev->ep_in[STM32_ENDPOINT_CMD_IN & 0xFU].is_used = 1U;
        
//        // DATA_OUT endpoint
//        USBD_LL_OpenEP(pdev, STM32_ENDPOINT_DATA_OUT, USBD_EP_TYPE_BULK, MAX_PACKET_SIZE);
//        pdev->ep_out[STM32_ENDPOINT_DATA_OUT & 0xFU].is_used = 1U;
    }
    
    /* Initialize Hardware layer */
    if (((USBD_DFU_MediaTypeDef *)pdev->pUserData)->Init() != USBD_OK)
    {
        return (uint8_t)USBD_FAIL;
    }
    
    USBD_LL_PrepareReceive(pdev, STM32_ENDPOINT_CMD_OUT, (uint8_t*)&hdfu->stm32Cmd, sizeof(hdfu->stm32Cmd));
    USBD_LL_Transmit(pdev, STM32_ENDPOINT_CMD_IN, randomDataBuf, sizeof(randomDataBuf));
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



static uint8_t USBD_DFU_DataIn(USBD_HandleTypeDef *pdev, uint8_t epnum)
{
    switch (epnum) {
    case (STM32_ENDPOINT_CMD_IN&0x7F): {
        USBD_LL_Transmit(pdev, STM32_ENDPOINT_CMD_IN, randomDataBuf, sizeof(randomDataBuf));
        break;
    }}
    
    return (uint8_t)USBD_OK;
}

static uint32_t vectorTableAddr __attribute__((section(".noinit")));
static uint8_t USBD_DFU_DataOut(USBD_HandleTypeDef *pdev, uint8_t epnum) {
    USBD_DFU_HandleTypeDef *hdfu = (USBD_DFU_HandleTypeDef *)pdev->pClassData;
    STM32LoaderCmd* cmd = &hdfu->stm32Cmd;
    const size_t packetLen = USBD_LL_GetRxDataSize(pdev, epnum);
    
    switch (epnum) {
    
    // CMD_OUT endpoint:
    //   Handle the supplied command
    case STM32_ENDPOINT_CMD_OUT: {
        // Verify that we received at least the command op
        if (packetLen < sizeof(cmd->op)) return USBD_FAIL;
        
        const size_t argLen = packetLen-sizeof(cmd->op);
        switch (cmd->op) {
        // Set LED command:
        case STM32LoaderCmdOp_SetLED: {
            // Verify that we got the right argument size
            if (argLen < sizeof(cmd->arg.setLED)) return USBD_FAIL;
            
            extern void setLed0(int on);
            extern void setLed1(int on);
            extern void setLed2(int on);
            extern void setLed3(int on);
            switch (cmd->arg.setLED.idx) {
            case 0: setLed0(cmd->arg.setLED.state); break;
            case 1: setLed1(cmd->arg.setLED.state); break;
            case 2: setLed2(cmd->arg.setLED.state); break;
            case 3: setLed3(cmd->arg.setLED.state); break;
            }
            
            break;
        }
        
        // Write data command:
        //   Stash the address we're writing to in `stm32DataAddr`,
        //   Prepare the DATA_OUT endpoint for writing at that address
        case STM32LoaderCmdOp_WriteData: {
            // Verify that we got the right argument size
            if (argLen < sizeof(cmd->arg.writeData)) return USBD_FAIL;
            hdfu->stm32DataAddr = cmd->arg.writeData.addr;
//            USBD_LL_PrepareReceive(pdev, STM32_ENDPOINT_DATA_OUT, (uint8_t*)hdfu->stm32DataAddr, MAX_PACKET_SIZE);
            break;
        }
        
        // Reset command:
        //   Stash the vector table address for access after we reset,
        //   Perform a software reset
        case STM32LoaderCmdOp_Reset: {
            // Verify we got the right argument size
            if (argLen < sizeof(cmd->arg.reset)) return USBD_FAIL;
            vectorTableAddr = cmd->arg.reset.vectorTableAddr;
            // Perform software reset
            NVIC_SystemReset();
            break;
        }}
        
        // Prepare to receive another command
        USBD_LL_PrepareReceive(pdev, STM32_ENDPOINT_CMD_OUT, (uint8_t*)&hdfu->stm32Cmd, sizeof(hdfu->stm32Cmd));
        break;
    }
    
//    // DATA_OUT endpoint:
//    //   Update the address that we're writing to,
//    //   Prepare ourself to receive more data
//    case STM32_ENDPOINT_DATA_OUT: {
//        hdfu->stm32DataAddr += packetLen;
//        // Only prepare for more data if this packet was the maximum size.
//        // Otherwise, this packet is the last packet (USB 2 spec 5.8.3:
//        //   "A bulk transfer is complete when the endpoint ... Transfers a
//        //   packet with a payload size less than wMaxPacketSize or
//        //   transfers a zero-length packet".)
//        if (packetLen == MAX_PACKET_SIZE) {
//            USBD_LL_PrepareReceive(pdev, STM32_ENDPOINT_DATA_OUT, (uint8_t*)hdfu->stm32DataAddr, MAX_PACKET_SIZE);
//        }
//        break;
//    }
    
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
