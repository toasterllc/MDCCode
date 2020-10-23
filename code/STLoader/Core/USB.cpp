#include "USB.h"
#include <stdbool.h>
#include "usbd_ctlreq.h"
#include "Event.h"

static uint8_t USBD_DFU_Init(USBD_HandleTypeDef* pdev, uint8_t cfgidx);
static uint8_t USBD_DFU_DeInit(USBD_HandleTypeDef* pdev, uint8_t cfgidx);
static uint8_t USBD_DFU_Setup(USBD_HandleTypeDef* pdev, USBD_SetupReqTypedef* req);
static uint8_t USBD_DFU_EP0_RxReady(USBD_HandleTypeDef* pdev);
static uint8_t USBD_DFU_EP0_TxReady(USBD_HandleTypeDef* pdev);
static uint8_t USBD_DFU_DataIn(USBD_HandleTypeDef* pdev, uint8_t epnum);
static uint8_t USBD_DFU_DataOut(USBD_HandleTypeDef* pdev, uint8_t epnum);
static uint8_t USBD_DFU_SOF(USBD_HandleTypeDef* pdev);
static uint8_t* USBD_DFU_GetCfgDesc(uint16_t* length);

Channel<USBCmdOutEvent, 3> USBCmdOutChannel;
Channel<USBDataOutEvent, 3> USBDataOutChannel;

static uint8_t* USBD_DFU_GetUsrStringDesc(USBD_HandleTypeDef* pdev, uint8_t index, uint16_t* length);

USBD_ClassTypeDef USBD_DFU = {
    USBD_DFU_Init,
    USBD_DFU_DeInit,
    USBD_DFU_Setup,
    USBD_DFU_EP0_TxReady,
    USBD_DFU_EP0_RxReady,
    USBD_DFU_DataIn,
    USBD_DFU_DataOut,
    USBD_DFU_SOF,
    nullptr,
    nullptr,
    USBD_DFU_GetCfgDesc,
    USBD_DFU_GetCfgDesc,
    USBD_DFU_GetCfgDesc,
    nullptr,
    USBD_DFU_GetUsrStringDesc
};

#define MAX_PACKET_SIZE             512

#define ST_EPADDR_CMD_OUT           0x01    // OUT endpoint
#define ST_EPADDR_CMD_IN            0x81    // IN endpoint (high bit 1 = IN)
#define ST_EPADDR_DATA_OUT          0x02    // OUT endpoint

#define EPNUM(addr)                 (addr & 0xF)

// USB DFU device Configuration Descriptor
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

static uint8_t USBD_DFU_Init(USBD_HandleTypeDef* pdev, uint8_t cfgidx) {
    USBD_DFU_HandleTypeDef* hdfu;
    
    // Allocate Audio structure
    hdfu = (USBD_DFU_HandleTypeDef*)USBD_malloc(sizeof(USBD_DFU_HandleTypeDef));
    
    if (!hdfu) {
        pdev->pClassData = nullptr;
        return (uint8_t)USBD_EMEM;
    }
    
    pdev->pClassData = (void*)hdfu;
    
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
    
    USBD_LL_PrepareReceive(pdev, ST_EPADDR_CMD_OUT, (uint8_t*)&hdfu->stDataOutBuf, sizeof(hdfu->stDataOutBuf));
    return (uint8_t)USBD_OK;
}

static uint8_t USBD_DFU_DeInit(USBD_HandleTypeDef* pdev, uint8_t cfgidx) {
    if (pdev->pClassData) {
        USBD_free(pdev->pClassData);
        pdev->pClassData = nullptr;
    }
    return (uint8_t)USBD_OK;
}

static uint8_t USBD_DFU_Setup(USBD_HandleTypeDef* pdev, USBD_SetupReqTypedef* req) {
    USBD_CtlError(pdev, req);
    return USBD_FAIL;
}

static uint8_t* USBD_DFU_GetCfgDesc(uint16_t* length) {
    *length = (uint16_t)sizeof(USBD_DFU_CfgDesc);
    return USBD_DFU_CfgDesc;
}

static uint8_t USBD_DFU_EP0_RxReady(USBD_HandleTypeDef* pdev) {
  return (uint8_t)USBD_OK;
}

static uint8_t USBD_DFU_EP0_TxReady(USBD_HandleTypeDef* pdev) {
  return (uint8_t)USBD_OK;
}

static uint8_t USBD_DFU_SOF(USBD_HandleTypeDef* pdev) {
  return (uint8_t)USBD_OK;
}

static uint8_t USBD_DFU_DataIn(USBD_HandleTypeDef* pdev, uint8_t epnum) {
    return (uint8_t)USBD_OK;
}

static uint8_t USBD_DFU_DataOut(USBD_HandleTypeDef* pdev, uint8_t epnum) {
    USBD_DFU_HandleTypeDef* hdfu = (USBD_DFU_HandleTypeDef*)pdev->pClassData;
    const size_t dataLen = USBD_LL_GetRxDataSize(pdev, epnum);
    
    switch (epnum) {
    
    // CMD_OUT endpoint
    case EPNUM(ST_EPADDR_CMD_OUT): {
        USBCmdOutChannel.writeTry(USBCmdOutEvent{
            .data = hdfu->stDataOutBuf,
            .dataLen = dataLen,
        });
        break;
    }
    
    // DATA_OUT endpoint
    case EPNUM(ST_EPADDR_DATA_OUT): {
        USBDataOutChannel.writeTry(USBDataOutEvent{
            .dataLen = dataLen,
        });
        break;
    }}
    
    return (uint8_t)USBD_OK;
}

static uint8_t* USBD_DFU_GetUsrStringDesc(USBD_HandleTypeDef* pdev, uint8_t index, uint16_t* length) {
    return nullptr;
}
