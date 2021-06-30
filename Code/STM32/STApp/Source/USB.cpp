#include "USB.h"
#include "Enum.h"
#include "STAppTypes.h"

void USB::init() {
    _super::init(true);
    
    // TODO: revisit FIFO sizes and max packet sizes:
    //   Rx/Tx FIFO size
    //   Max packet size in USB descriptor
    //   MPSIZ (max packet size) in OTG_DIEPCTLx/OTG_DOEPCTLx
    //   PKTCNT (packet count) in OTG_DIEPTSIZx/OTG_DOEPTSIZx
    //   XFRSIZ (transfer size) in OTG_DIEPTSIZx/OTG_DOEPTSIZx
    //   
    //   The max packet size in the descriptor is defined by the USB spec,
    //   and is often larger than what we want, especially for BULK endpoints
    //   used for commands. In such cases, we should try making MPSIZ the actual
    //   max packet size that we want (which would be smaller than the
    //   max packet size in the descriptor) and make sure that when the host 
    //   sends us a larger packet than this amount, MPSIZ causes the excess data
    //   to be rejected.
    
    // ## Set Rx/Tx FIFO sizes. Notes:
    // - OTG HS FIFO RAM is 4096 bytes, and must be shared amongst all endpoints.
    // - FIFO sizes (supplied as arguments below) have units of 4-byte words.
    
    // # Set Rx FIFO sizes, shared by all OUT endpoints (GRXFSIZ register):
    //   "The OTG peripheral uses a single receive FIFO that receives
    //   the data directed to all OUT endpoints."
    // TODO: revisit Rx FIFO sizing -- see RM 32.11.3
    HAL_PCDEx_SetRxFiFo(&_pcd, 64);
    
    // # Set Tx FIFO sizes (IN endpoints; DIEPTXF0 register)
    // - "The minimum RAM space required for each IN endpoint's transmit FIFO
    //   is the maximum packet size for that particular IN endpoint."
    // - "More space allocated in the transmit IN endpoint FIFO results in
    //   better performance on the USB."
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(STApp::Endpoints::Ctrl), 16);
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(STApp::Endpoints::CmdOut), 4);
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(STApp::Endpoints::PixIn), 768);
}

void USB::resetFinish() {
    // Disable interrupts while we reset our endpoints, to prevent
    // USB interrupts from corrupting the reset process.
    IRQState irq;
    irq.disable();
    
    // Reset our channels so there are no pending events
    resetChannel.reset();
    cmdChannel.reset();
    pixChannel.reset();
    
    // Reset all endpoints to return them to the default state.
    // USB_ResetEndpoints() requires that SETUP packets aren't
    // received while it's executing. (See comment within
    // USB_ResetEndpoints().)
    //
    // This requirement necessitates a contract between the device
    // and the USB host: during the time between the host sending
    // the reset control request and receiving our response, the host
    // must not send any control requests. (This should be easily met
    // since control requests are typically synchronous.) This contact
    // guarantees that SETUP packets aren't delivered while
    // USB_ResetEndpoints() is executing.
    USB_ResetEndpoints(_pcd.Instance, _pcd.Init.dev_endpoints);
    // Reply to the reset control request
    USBD_CtlSendStatus(&_device);
}

USBD_StatusTypeDef USB::cmdRecv() {
    return USBD_LL_PrepareReceive(&_device, STApp::Endpoints::CmdOut, _cmdBuf, sizeof(_cmdBuf));
}

USBD_StatusTypeDef USB::cmdSend(const void* data, size_t len) {
    // TODO: if this function is called twice, the second call will clobber the first.
    //       the second call should fail (returning BUSY) until the data is finished sending from the first call.
    return USBD_LL_Transmit(&_device, STApp::Endpoints::CmdIn, (uint8_t*)data, len);
}

USBD_StatusTypeDef USB::pixSend(const void* data, size_t len) {
    // TODO: if this function is called twice, the second call will clobber the first.
    //       the second call should fail (returning BUSY) until the data is finished sending from the first call.
    return USBD_LL_Transmit(&_device, STApp::Endpoints::PixIn, (uint8_t*)data, len);
}

uint8_t USB::_usbd_Init(uint8_t cfgidx) {
    _super::_usbd_Init(cfgidx);
    
    // Open endpoints
    {
        // CmdOut endpoint
        USBD_LL_OpenEP(&_device, STApp::Endpoints::CmdOut, USBD_EP_TYPE_BULK, MaxPacketSize::Cmd);
        _device.ep_out[EndpointNum(STApp::Endpoints::CmdOut)].is_used = 1U;
        
        // CmdIn endpoint
        USBD_LL_OpenEP(&_device, STApp::Endpoints::CmdIn, USBD_EP_TYPE_BULK, MaxPacketSize::Cmd);
        _device.ep_out[EndpointNum(STApp::Endpoints::CmdIn)].is_used = 1U;
        
        // PixIn endpoint
        USBD_LL_OpenEP(&_device, STApp::Endpoints::PixIn, USBD_EP_TYPE_BULK, MaxPacketSize::Data);
        _device.ep_in[EndpointNum(STApp::Endpoints::PixIn)].is_used = 1U;
    }
    
    return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_DeInit(uint8_t cfgidx) {
    return _super::_usbd_DeInit(cfgidx);
}

uint8_t USB::_usbd_Setup(USBD_SetupReqTypedef* req) {
    switch (req->bmRequest & USB_REQ_TYPE_MASK) {
    case USB_REQ_TYPE_VENDOR: {
        switch (req->bRequest) {
        case STApp::CtrlReqs::Reset: {
            resetChannel.writeTry(Signal{});
            return USBD_OK;
        }
        
        default: {
            USBD_CtlError(&_device, req);
            break;
        }}
        break;
    }
    
    default: {
        USBD_CtlError(&_device, req);
        break;
    }}
    
    return USBD_FAIL;
}

uint8_t USB::_usbd_EP0_TxSent() {
    return _super::_usbd_EP0_TxSent();
}

uint8_t USB::_usbd_EP0_RxReady() {
    return _super::_usbd_EP0_RxReady();
}

uint8_t USB::_usbd_DataIn(uint8_t epnum) {
    _super::_usbd_DataIn(epnum);
    
    switch (epnum) {
    // PixIn endpoint
    case EndpointNum(STApp::Endpoints::PixIn): {
        pixChannel.writeTry(Signal{});
        break;
    }}
    
    return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_DataOut(uint8_t epnum) {
    _super::_usbd_DataOut(epnum);
    
    const size_t dataLen = USBD_LL_GetRxDataSize(&_device, epnum);
    switch (epnum) {
    // CmdOut endpoint
    case EndpointNum(STApp::Endpoints::CmdOut): {
        cmdChannel.writeTry(Cmd{
            .data = _cmdBuf,
            .len = dataLen,
        });
        break;
    }}
    
    return (uint8_t)USBD_OK;
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
    constexpr size_t descLen = 39;
    static uint8_t desc[] = {
        // Configuration descriptor
        0x09,                                       // bLength: configuration descriptor length
        USB_DESC_TYPE_CONFIGURATION,                // bDescriptorType: configuration descriptor
        LOBYTE(descLen), HIBYTE(descLen),           // wTotalLength: total descriptor length
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
            0x03,                                       // bNumEndpoints
            0xFF,                                       // bInterfaceClass: vendor specific
            0x00,                                       // bInterfaceSubClass
            0x00,                                       // nInterfaceProtocol
            0x00,                                       // iInterface: string descriptor index
            
                // CmdOut endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                STApp::Endpoints::CmdOut,                                   // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Cmd), HIBYTE(MaxPacketSize::Cmd),     // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
                
                // CmdIn endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                STApp::Endpoints::CmdIn,                                    // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Data), HIBYTE(MaxPacketSize::Data),   // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
                
                // PixIn endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                STApp::Endpoints::PixIn,                                    // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Data), HIBYTE(MaxPacketSize::Data),   // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
    };
    static_assert(sizeof(desc)==descLen, "descLen invalid");
    
    *len = (uint16_t)descLen;
    return desc;
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
