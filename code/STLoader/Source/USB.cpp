#include "USB.h"
#include <stdbool.h>
#include "stm32f7xx.h"
#include "usbd_core.h"
#include "usbd_ctlreq.h"
#include "usbd_def.h"
#include "usbd_desc.h"
#include "Enum.h"
#include "STLoaderTypes.h"
#include "usbd_ioreq.h"

constexpr size_t MaxPacketSize = 512;

Enum(uint8_t, Endpoint, Endpoints,
    // OUT endpoints (high bit 0)
    STCmdOut        = 0x01,
    STDataOut       = 0x02,
    ICECmdOut       = 0x03,
    ICEDataOut      = 0x04,
    
    // IN endpoints (high bit 1)
    STStatusIn      = 0x81,
    ICEStatusIn     = 0x82,
);

static constexpr uint8_t EndpointNum(Endpoint ep) {
    return ep&0xF;
}

void USB::init() {
    USBD_StatusTypeDef us = USBD_Init(&_device, &HS_Desc, DEVICE_HS, this);
    assert(us == USBD_OK);
    
    _pcd.pData = &_device;
    _device.pData = &_pcd;
    
    _pcd.Instance = USB_OTG_HS;
    _pcd.Init.dev_endpoints = 9;
    _pcd.Init.dma_enable = DISABLE;
    _pcd.Init.phy_itface = USB_OTG_HS_EMBEDDED_PHY;
    _pcd.Init.sof_enable = DISABLE;
    _pcd.Init.low_power_enable = DISABLE;
    _pcd.Init.lpm_enable = DISABLE;
    _pcd.Init.vbus_sensing_enable = DISABLE;
    _pcd.Init.use_dedicated_ep1 = DISABLE;
    _pcd.Init.use_external_vbus = DISABLE;
    HAL_StatusTypeDef hs = HAL_PCD_Init(&_pcd);
    assert(hs == HAL_OK);
    
    // Set Rx FIFO sizes (OUT endpoints)
    HAL_PCDEx_SetRxFiFo(&_pcd, 512);
    // Set Tx FIFO sizes (IN endpoints)
    HAL_PCDEx_SetTxFiFo(&_pcd, 0, 128); // Control endpoint
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::STStatusIn), 64);
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::ICEStatusIn), 64);
    
#define Fwd0(name) [](USBD_HandleTypeDef* pdev) { return ((USB*)pdev->pCtx)->_usbd_##name(); }
#define Fwd1(name, T0) [](USBD_HandleTypeDef* pdev, T0 t0) { return ((USB*)pdev->pCtx)->_usbd_##name(t0); }
#define Fwd2(name, T0, T1) [](USBD_HandleTypeDef* pdev, T0 t0, T1 t1) { return ((USB*)pdev->pCtx)->_usbd_##name(t0, t1); }
    
    static const USBD_ClassTypeDef usbClass = {
        .Init                           = Fwd1(Init, uint8_t),
        .DeInit                         = Fwd1(DeInit, uint8_t),
        .Setup                          = Fwd1(Setup, USBD_SetupReqTypedef*),
        .EP0_TxSent                     = Fwd0(EP0_TxSent),
        .EP0_RxReady                    = Fwd0(EP0_RxReady),
        .DataIn                         = Fwd1(DataIn, uint8_t),
        .DataOut                        = Fwd1(DataOut, uint8_t),
        .SOF                            = Fwd0(SOF),
        .IsoINIncomplete                = nullptr,
        .IsoOUTIncomplete               = nullptr,
        .GetHSConfigDescriptor          = Fwd1(GetConfigDescriptor, uint16_t*),
        .GetFSConfigDescriptor          = Fwd1(GetConfigDescriptor, uint16_t*),
        .GetOtherSpeedConfigDescriptor  = Fwd1(GetConfigDescriptor, uint16_t*),
        .GetDeviceQualifierDescriptor   = nullptr,
        .GetUsrStrDescriptor            = Fwd2(GetUsrStrDescriptor, uint8_t, uint16_t*),
    };
    
#undef Fwd0
#undef Fwd1
#undef Fwd2
    
    us = USBD_RegisterClass(&_device, &usbClass);
    assert(us == USBD_OK);
    
    us = USBD_Start(&_device);
    assert(us == USBD_OK);
}

USB::State USB::state() const {
    return _state;
}

USBD_StatusTypeDef USB::stRecvCmd() {
    return USBD_LL_PrepareReceive(&_device, Endpoints::STCmdOut, _stCmdBuf, sizeof(_stCmdBuf));
}

USBD_StatusTypeDef USB::stRecvData(void* addr, size_t len) {
    return USBD_LL_PrepareReceive(&_device, Endpoints::STDataOut, (uint8_t*)addr, len);
}

USBD_StatusTypeDef USB::stSendStatus(void* data, size_t len) {
    // TODO: if this function is called twice, the second call will clobber the first.
    //       the second call should fail (returning BUSY) until the data is finished sending from the first call.
    return USBD_LL_Transmit(&_device, Endpoints::STStatusIn, (uint8_t*)data, len);
}

USBD_StatusTypeDef USB::iceRecvCmd() {
    return USBD_LL_PrepareReceive(&_device, Endpoints::ICECmdOut, _iceCmdBuf, sizeof(_iceCmdBuf));
}

USBD_StatusTypeDef USB::iceRecvData(void* addr, size_t len) {
    return USBD_LL_PrepareReceive(&_device, Endpoints::ICEDataOut, (uint8_t*)addr, len);
}

USBD_StatusTypeDef USB::iceSendStatus(void* data, size_t len) {
    // TODO: if this function is called twice, the second call will clobber the first.
    //       the second call should fail (returning BUSY) until the data is finished sending from the first call.
    return USBD_LL_Transmit(&_device, Endpoints::ICEStatusIn, (uint8_t*)data, len);
}

void USB::_isr() {
    ISR_HAL_PCD(&_pcd);
}

uint8_t USB::_usbd_Init(uint8_t cfgidx) {
    // Open endpoints
    
    // STM32 endpoints
    {
        // STCmdOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::STCmdOut, USBD_EP_TYPE_BULK, MaxPacketSize);
        _device.ep_out[EndpointNum(Endpoints::STCmdOut)].is_used = 1U;
        
        // STDataOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::STDataOut, USBD_EP_TYPE_BULK, MaxPacketSize);
        _device.ep_out[EndpointNum(Endpoints::STDataOut)].is_used = 1U;
        
        // STStatusIn endpoint
        USBD_LL_OpenEP(&_device, Endpoints::STStatusIn, USBD_EP_TYPE_BULK, MaxPacketSize);
        _device.ep_in[EndpointNum(Endpoints::STStatusIn)].is_used = 1U;
    }
    
    // ICE40 endpoints
    {
        // ICECmdOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::ICECmdOut, USBD_EP_TYPE_BULK, MaxPacketSize);
        _device.ep_out[EndpointNum(Endpoints::ICECmdOut)].is_used = 1U;
        
        // ICEDataOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::ICEDataOut, USBD_EP_TYPE_BULK, MaxPacketSize);
        _device.ep_out[EndpointNum(Endpoints::ICEDataOut)].is_used = 1U;
        
        // ICEStatusIn endpoint
        USBD_LL_OpenEP(&_device, Endpoints::ICEStatusIn, USBD_EP_TYPE_BULK, MaxPacketSize);
        _device.ep_in[EndpointNum(Endpoints::ICEStatusIn)].is_used = 1U;
    }
    
    _state = State::Connected;
    eventChannel.writeTry(Event{
        .type = Event::Type::StateChanged,
    });
    
    return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_DeInit(uint8_t cfgidx) {
    _state = State::Disconnected;
    eventChannel.writeTry(Event{
        .type = Event::Type::StateChanged,
    });
    return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_Setup(USBD_SetupReqTypedef* req) {
    USBD_CtlError(&_device, req);
    return USBD_FAIL;
}

uint8_t USB::_usbd_EP0_TxSent() {
  return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_EP0_RxReady() {
  return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_DataIn(uint8_t epnum) {
    return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_DataOut(uint8_t epnum) {
    const size_t dataLen = USBD_LL_GetRxDataSize(&_device, epnum);
    
    switch (epnum) {
    
    // STCmdOut endpoint
    case EndpointNum(Endpoints::STCmdOut): {
        stCmdChannel.writeTry(Cmd{
            .data = _stCmdBuf,
            .len = dataLen,
        });
        break;
    }
    
    // STDataOut endpoint
    case EndpointNum(Endpoints::STDataOut): {
        stDataChannel.writeTry(Data{
            .len = dataLen,
        });
        break;
    }
    
    // ICECmdOut endpoint
    case EndpointNum(Endpoints::ICECmdOut): {
        iceCmdChannel.writeTry(Cmd{
            .data = _iceCmdBuf,
            .len = dataLen,
        });
        break;
    }
    
    // ICEDataOut endpoint
    case EndpointNum(Endpoints::ICEDataOut): {
        iceDataChannel.writeTry(Data{
            .len = dataLen,
        });
        break;
    }}
    
    return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_SOF() {
  return (uint8_t)USBD_OK;
}

uint8_t* USB::_usbd_GetConfigDescriptor(uint16_t* len) {
    // USB DFU device Configuration Descriptor
    constexpr size_t descLen = 69;
    static uint8_t desc[] = {
        // Configuration descriptor
        0x09,                                       // bLength: configuration descriptor length
        USB_DESC_TYPE_CONFIGURATION,                // bDescriptorType: configuration descriptor
        LOBYTE(descLen), HIBYTE(descLen),           // wTotalLength: total descriptor length
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
            0x03,                                       // bNumEndpoints
            0xFF,                                       // bInterfaceClass: vendor specific
            0x00,                                       // bInterfaceSubClass
            0x00,                                       // nInterfaceProtocol
            0x00,                                       // iInterface: string descriptor index
            
                // STCmdOut endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                Endpoints::STCmdOut,                                        // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize), HIBYTE(MaxPacketSize),               // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
                
                // STDataOut endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                Endpoints::STDataOut,                                       // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize), HIBYTE(MaxPacketSize),               // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
                
                // STStatusIn endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                Endpoints::STStatusIn,                                      // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize), HIBYTE(MaxPacketSize),               // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
            
            // Interface descriptor: ICE40 bootloader
            0x09,                                       // bLength: interface descriptor length
            USB_DESC_TYPE_INTERFACE,                    // bDescriptorType: interface descriptor
            0x01,                                       // bInterfaceNumber: Number of Interface
            0x00,                                       // bAlternateSetting: Alternate setting
            0x03,                                       // bNumEndpoints
            0xFF,                                       // bInterfaceClass: vendor specific
            0x00,                                       // bInterfaceSubClass
            0x00,                                       // nInterfaceProtocol
            0x00,                                       // iInterface: string descriptor index
            
                // ICECmdOut endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                Endpoints::ICECmdOut,                                       // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize), HIBYTE(MaxPacketSize),               // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
                
                // ICEDataOut endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                Endpoints::ICEDataOut,                                      // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize), HIBYTE(MaxPacketSize),               // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
                
                // ICEStatusIn endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                Endpoints::ICEStatusIn,                                     // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize), HIBYTE(MaxPacketSize),               // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
    };
    static_assert(sizeof(desc)==descLen, "descLen invalid");
    
    *len = (uint16_t)descLen;
    return desc;
}

uint8_t* USB::_usbd_GetUsrStrDescriptor(uint8_t index, uint16_t* len) {
    return nullptr;
}
