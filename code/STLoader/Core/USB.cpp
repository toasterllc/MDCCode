#include "USB.h"
#include <stdbool.h>
#include "stm32f7xx.h"
#include "stm32f7xx_hal.h"
#include "usbd_core.h"
#include "usbd_ctlreq.h"
#include "usbd_def.h"
#include "usbd_desc.h"
#include "Enum.h"
#include "STLoaderTypes.h"
#include "usbd_ioreq.h"

constexpr size_t MaxPacketSize = 512;

Enum(uint8_t, Endpoint, Endpoints,
    CmdOut      = 0x01,     // OUT endpoint
    CmdIn       = 0x81,     // IN endpoint (high bit 1 = IN)
    DataOut     = 0x02,     // OUT endpoint
);

static constexpr uint8_t EndpointNum(Endpoint ep) {
    return ep&0xF;
}

void USB::init() {
    USBD_StatusTypeDef ur = USBD_Init(&_device, &HS_Desc, DEVICE_HS, this);
    assert(ur == USBD_OK);

#define Fwd0(name) [](void* ctx) { return ((USB*)ctx)->_usbd_##name(); }
#define Fwd1(name, T0) [](void* ctx, T0 t0) { return ((USB*)ctx)->_usbd_##name(t0); }
#define Fwd2(name, T0, T1) [](void* ctx, T0 t0, T1 t1) { return ((USB*)ctx)->_usbd_##name(t0, t1); }
    
    USBD_ClassTypeDef usbClass = {
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
    
    ur = USBD_RegisterClass(&_device, &usbClass);
    assert(ur == USBD_OK);
    
    ur = USBD_Start(&_device);
    assert(ur == USBD_OK);
    
    // Open endpoints
    // CMD_OUT endpoint
    USBD_LL_OpenEP(&_device, Endpoints::CmdOut, USBD_EP_TYPE_BULK, MaxPacketSize);
    _device.ep_out[EndpointNum(Endpoints::CmdOut)].is_used = 1U;
    
    // CMD_IN endpoint
    USBD_LL_OpenEP(&_device, Endpoints::CmdIn, USBD_EP_TYPE_BULK, MaxPacketSize);
    _device.ep_in[EndpointNum(Endpoints::CmdIn)].is_used = 1U;
    
    // DATA_OUT endpoint
    USBD_LL_OpenEP(&_device, Endpoints::DataOut, USBD_EP_TYPE_BULK, MaxPacketSize);
    _device.ep_out[EndpointNum(Endpoints::DataOut)].is_used = 1U;
}

USBD_StatusTypeDef USB::recvCmdOut() {
    return USBD_LL_PrepareReceive(&_device, Endpoints::CmdOut, _cmdOutBuf, sizeof(_cmdOutBuf));
}

USBD_StatusTypeDef USB::recvDataOut(void* addr) {
    // Restrict writing to the allowed range in RAM
    extern uint8_t _sram_app[];
    extern uint8_t _eram_app[];
    if (addr<_sram_app || addr>=_eram_app) return USBD_FAIL;
    const size_t len = (uintptr_t)_eram_app-(uintptr_t)addr;
    return USBD_LL_PrepareReceive(&_device, Endpoints::DataOut, (uint8_t*)addr, len);
}

USBD_StatusTypeDef USB::sendCmdIn(void* data, size_t len) {
    return USBD_LL_Transmit(&_device, Endpoints::CmdIn, (uint8_t*)data, len);
}

uint8_t USB::_usbd_Init(uint8_t cfgidx) {
    return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_DeInit(uint8_t cfgidx) {
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
    
    // CMD_OUT endpoint
    case EndpointNum(Endpoints::CmdOut): {
        cmdOutChannel.writeTry(CmdOutEvent{
            .data = _cmdOutBuf,
            .dataLen = dataLen,
        });
        break;
    }
    
    // DATA_OUT endpoint
    case EndpointNum(Endpoints::DataOut): {
        dataOutChannel.writeTry(DataOutEvent{
            .dataLen = dataLen,
            .end = (dataLen != MaxPacketSize),
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
    constexpr size_t descLen = 39;
    static uint8_t desc[descLen] = {
        // Configuration descriptor
        0x09,                                       // bLength: configuration descriptor length
        USB_DESC_TYPE_CONFIGURATION,                // bDescriptorType: configuration descriptor
        LOBYTE(descLen), HIBYTE(descLen),           // wTotalLength: total descriptor length
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
                Endpoints::CmdOut,                                          // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize), HIBYTE(MaxPacketSize),               // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
                
                // CMD_IN endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                Endpoints::CmdIn,                                           // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize), HIBYTE(MaxPacketSize),               // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
                
                // DATA_OUT endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                Endpoints::DataOut,                                         // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize), HIBYTE(MaxPacketSize),               // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
    };
    
    *len = (uint16_t)descLen;
    return desc;
}

uint8_t* USB::_usbd_GetUsrStrDescriptor(uint8_t index, uint16_t* len) {
    return nullptr;
}
