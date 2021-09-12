#include "USB.h"
#include "Toastbox/Enum.h"
#include <algorithm>
using namespace STApp;

void USB::reset() {
    // Disable interrupts while we reset our endpoints, to prevent
    // USB interrupts from corrupting the reset process.
    IRQState irq;
    irq.disable();
    
    // Reset our channels so there are no pending events
    cmdRecvChannel.reset();
    dataSendChannel.reset();
    
    // Reset state
    _dataSendBusy = false;
    
    // Reset all endpoints to return them to the default state.
    // USB_ResetEndpoints() requires that SETUP packets aren't
    // received while it's executing. (See comment within
    // USB_ResetEndpoints().)
    //
    // This requirement necessitates a contract between the device
    // and the USB host: during the time between the host sending
    // the reset control request and receiving our response, the host
    // must not send any control requests. (This should be easily met
    // since control requests are typically synchronous.) This contract
    // guarantees that SETUP packets aren't delivered while
    // USB_ResetEndpoints() is executing.
    USB_ResetEndpoints(_pcd.Instance, _pcd.Init.dev_endpoints);
}

void USB::cmdSendStatus(bool status) {
    if (status) USBD_CtlSendStatus(&_device);
    else        USBD_CtlError(&_device, nullptr);
}

USBD_StatusTypeDef USB::dataSend(const void* data, size_t len) {
    Assert(!_dataSendBusy);
    _dataSendBusy = true;
    return USBD_LL_Transmit(&_device, STApp::Endpoints::DataIn, (uint8_t*)data, len);
}

uint8_t USB::_usbd_Init(uint8_t cfgidx) {
    return _super::_usbd_Init(cfgidx);
}

uint8_t USB::_usbd_DeInit(uint8_t cfgidx) {
    return _super::_usbd_DeInit(cfgidx);
}

uint8_t USB::_usbd_Setup(USBD_SetupReqTypedef* req) {
    switch (req->bmRequest & USB_REQ_TYPE_MASK) {
    case USB_REQ_TYPE_VENDOR: {
        switch (req->bRequest) {
        case STApp::CtrlReqs::CmdExec: {
            USBD_CtlPrepareRx(&_device, _cmdRecvBuf, sizeof(_cmdRecvBuf));
            return USBD_OK;
        }
        
        default: break;
        }
        break;
    }
    
    default: break;
    }
    
    USBD_CtlError(&_device, req);
    return USBD_FAIL;
}

uint8_t USB::_usbd_EP0_TxSent() {
    return _super::_usbd_EP0_TxSent();
}

uint8_t USB::_usbd_EP0_RxReady() {
    _super::_usbd_EP0_RxReady();
    
    const size_t dataLen = USBD_LL_GetRxDataSize(&_device, 0);
    cmdRecvChannel.writeTry(CmdRecv{
        .data = _cmdRecvBuf,
        .len = dataLen,
    });
    
    return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_DataIn(uint8_t epnum) {
    _super::_usbd_DataIn(epnum);
    
    switch (epnum) {
    // DataIn endpoint
    case EndpointIdx(STApp::Endpoints::DataIn): {
        dataSendChannel.writeTry(DataSend{});
        _dataSendBusy = false;
        break;
    }}
    
    return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_DataOut(uint8_t epnum) {
    return _super::_usbd_DataOut(epnum);
}

uint8_t USB::_usbd_SOF() {
  return _super::_usbd_SOF();
}

uint8_t USB::_usbd_IsoINIncomplete(uint8_t epnum) {
    return _super::_usbd_IsoINIncomplete(epnum);
}

uint8_t USB::_usbd_IsoOUTIncomplete(uint8_t epnum) {
    return _super::_usbd_IsoOUTIncomplete(epnum);
}

uint8_t* USB::_usbd_GetHSConfigDescriptor(uint16_t* len) {
    _super::_usbd_GetHSConfigDescriptor(len);
    
    // USB DFU device Configuration Descriptor
    constexpr size_t DescLen = 25;
    static uint8_t Desc[] = {
        // Configuration descriptor
        0x09,                                       // bLength: configuration descriptor length
        USB_DESC_TYPE_CONFIGURATION,                // bDescriptorType: configuration descriptor
        LOBYTE(DescLen), HIBYTE(DescLen),           // wTotalLength: total descriptor length
        0x01,                                       // bNumInterfaces: 1 interface
        0x01,                                       // bConfigurationValue: config 1
        0x00,                                       // iConfiguration: string descriptor index
        0x80,                                       // bmAttributes: bus powered
        0xFA,                                       // bMaxPower: 500 mA (2 mA units)
        
            // Interface descriptor
            0x09,                                       // bLength: interface descriptor length
            USB_DESC_TYPE_INTERFACE,                    // bDescriptorType: interface descriptor
            0x00,                                       // bInterfaceNumber: interface index
            0x00,                                       // bAlternateSetting: alternate setting
            0x01,                                       // bNumEndpoints
            0xFF,                                       // bInterfaceClass: vendor specific
            0x00,                                       // bInterfaceSubClass
            0x00,                                       // nInterfaceProtocol
            0x00,                                       // iInterface: string descriptor index
            
                // DataIn endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                STApp::Endpoints::DataIn,                                   // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSizeIn()), HIBYTE(MaxPacketSizeIn()),       // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
    };
    static_assert(sizeof(Desc)==DescLen, "DescLen invalid");
    
    *len = (uint16_t)DescLen;
    return Desc;
}

uint8_t* USB::_usbd_GetFSConfigDescriptor(uint16_t* len) {
    _super::_usbd_GetFSConfigDescriptor(len);
    return _usbd_GetHSConfigDescriptor(len);
}

// TODO: did we used to call _usbd_GetHSConfigDescriptor for this?
uint8_t* USB::_usbd_GetOtherSpeedConfigDescriptor(uint16_t* len) {
    _super::_usbd_GetOtherSpeedConfigDescriptor(len);
    return _usbd_GetHSConfigDescriptor(len);
}

// TODO: did we used to call _usbd_GetHSConfigDescriptor for this?
uint8_t* USB::_usbd_GetDeviceQualifierDescriptor(uint16_t* len) {
    _super::_usbd_GetDeviceQualifierDescriptor(len);
    return _usbd_GetHSConfigDescriptor(len);
}

uint8_t* USB::_usbd_GetUsrStrDescriptor(uint8_t index, uint16_t* len) {
    return _super::_usbd_GetUsrStrDescriptor(index, len);
}
