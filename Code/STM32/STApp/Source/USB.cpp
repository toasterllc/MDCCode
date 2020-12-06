#include "USB.h"
#include "Enum.h"
#include "STAppTypes.h"

Enum(uint8_t, Endpoint, Endpoints,
    Control = 0x00,
    
    // OUT endpoints (high bit 0)
    CmdOut  = 0x01,
    
    // IN endpoints (high bit 1)
    PixIn   = 0x81,
);

void USB::init() {
    _super::init(true);
    
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
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::Control), 16);
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::PixIn), 768);
}

static bool setIgnoreOUTTransactions(USBD_HandleTypeDef* pdev, bool ignore) {
    const PCD_HandleTypeDef* hpcd = (PCD_HandleTypeDef*)pdev->pData;
    const USB_OTG_GlobalTypeDef* USBx = hpcd->Instance;
    const uint32_t USBx_BASE = (uint32_t)USBx;
    auto& OTG_GINTSTS = USBx->GINTSTS;
    auto& OTG_DCTL = USBx_DEVICE->DCTL;
    
    const uint32_t mask = USB_OTG_GINTMSK_GONAKEFFM;
    const uint32_t set = USB_OTG_DCTL_SGONAK;
    const uint32_t clear = USB_OTG_DCTL_CGONAK;
    
    IRQState irq;
    irq.disable();
    
    // We have to check what state "Global OUT NAK" is in. If it's already
    // in the state we want it in, we don't do anything:
    //
    //   "The application must set [SGONAK] only after making sure that
    //   the Global OUT NAK effective bit in the core interrupt register
    //   (GONAKEFF bit in OTG_GINTSTS) is cleared."
    const bool state = OTG_GINTSTS&mask;
    if (!state && ignore) {
        OTG_DCTL |= set;
        while (!(OTG_GINTSTS & mask));
    
    } else if (state && !ignore) {
        OTG_DCTL |= clear;
        while (OTG_GINTSTS & mask);
    }
    return state;
}

static bool setIgnoreINTransactions(USBD_HandleTypeDef* pdev, bool ignore) {
    const PCD_HandleTypeDef* hpcd = (PCD_HandleTypeDef*)pdev->pData;
    const USB_OTG_GlobalTypeDef* USBx = hpcd->Instance;
    const uint32_t USBx_BASE = (uint32_t)USBx;
    auto& OTG_GINTSTS = USBx->GINTSTS;
    auto& OTG_DCTL = USBx_DEVICE->DCTL;
    
    const uint32_t mask = USB_OTG_GINTMSK_GINAKEFFM;
    const uint32_t set = USB_OTG_DCTL_SGINAK;
    const uint32_t clear = USB_OTG_DCTL_CGINAK;
    
    IRQState irq;
    irq.disable();
    
    // We have to check what state "Global IN NAK" is in. If it's already
    // in the state we want it in, we don't do anything:
    //
    //   "The application must set [SGINAK] only after making sure that
    //   the Global IN NAK effective bit in the core interrupt register
    //   (GINAKEFF bit in OTG_GINTSTS) is cleared."
    const bool state = OTG_GINTSTS&mask;
    if (!state && ignore) {
        OTG_DCTL |= set;
        while (!(OTG_GINTSTS & mask));
    
    } else if (state && !ignore) {
        OTG_DCTL |= clear;
        while (OTG_GINTSTS & mask);
    }
    return state;
}

static void resetEndpoints(USBD_HandleTypeDef* pdev) {
    PCD_HandleTypeDef* hpcd = (PCD_HandleTypeDef*)pdev->pData;
    USB_OTG_GlobalTypeDef* USBx = hpcd->Instance;
    uint32_t USBx_BASE = (uint32_t)USBx;
    
    IRQState irq;
    irq.disable();
    
    // NAK all transactions while we reset our endpoints
    bool oldIgnoreINTransactions = setIgnoreINTransactions(pdev, true);
    bool oldIgnoreOUTTransactions = setIgnoreOUTTransactions(pdev, true);
    
    // Abort all underway transfers on all endpoints,
    // and reset their PIDs to DATA0
    for (uint8_t i=0; i<hpcd->Init.dev_endpoints; i++) {
        // IN endpoint handling
        {
            auto epin = USBx_INEP(i);
            auto& DIEPCTL = epin->DIEPCTL;
            auto& DIEPINT = epin->DIEPINT;
            
            if (DIEPCTL & USB_OTG_DIEPCTL_USBAEP) {
                // Check if transfer in progress
                if (DIEPCTL & USB_OTG_DIEPCTL_EPENA) {
                    // Set endpoint SNAK if it was disabled, and wait for completion
                    if (!(DIEPINT & USB_OTG_DIEPINT_INEPNE)) {
                        DIEPCTL |= USB_OTG_DIEPCTL_SNAK;
                        while (!(DIEPINT & USB_OTG_DIEPINT_INEPNE));
                    }
                    
                    // Disable the endpoint (set EPDIS) and wait for completion
                    // Clear USB_OTG_DIEPCTL_EPENA here, since setting it to 1 enables the endpoint.
                    DIEPCTL |= USB_OTG_DIEPCTL_EPDIS;
                    while (!(DIEPINT & USB_OTG_DIEPINT_EPDISD));
                    // Verify that EPDIS is cleared: "The core clears [EPDIS] before
                    // setting the endpoint disabled interrupt."
                    Assert(!(DIEPCTL & USB_OTG_DIEPCTL_EPDIS));
                    // Clear EPDISD
                    DIEPINT = USB_OTG_DIEPINT_EPDISD;
                
                } else {
                    // Don't wait for completion via INEPNE, because that interrupt bit
                    // is only set when a transfer is underway (DIEPCTL.EPENA=1)
                    DIEPCTL |= USB_OTG_DIEPCTL_SNAK;
                }
                
                // Clear STALL
                DIEPCTL &= ~USB_OTG_DIEPCTL_STALL;
                // Reset PID to DATA0
                DIEPCTL |= USB_OTG_DIEPCTL_SD0PID_SEVNFRM;
            }
        }
        
        // OUT endpoint handling
        {
            auto epout = USBx_OUTEP(i);
            auto& DOEPCTL = epout->DOEPCTL;
            auto& DOEPINT = epout->DOEPINT;
            
            if (DOEPCTL & USB_OTG_DOEPCTL_USBAEP) {
                // Check if transfer in progress
                if (DOEPCTL & USB_OTG_DOEPCTL_EPENA) {
                    // Skip endpoint 0, since it can't be disabled
                    if (i) {
                        // Disable the endpoint (set EPDIS) and wait for completion
                        // Clear USB_OTG_DOEPCTL_EPENA here, since setting it to 1 enables the endpoint.
                        DOEPCTL |= USB_OTG_DOEPCTL_EPDIS;
                        while (!(DOEPINT & USB_OTG_DOEPINT_EPDISD));
                        // Verify that EPDIS is cleared: "The core clears [EPDIS] before
                        // setting the endpoint disabled interrupt."
                        Assert(!(DOEPCTL & USB_OTG_DOEPCTL_EPDIS));
                        // Clear EPDISD
                        DOEPINT = USB_OTG_DOEPINT_EPDISD;
                    }
                }
                
                // Set endpoint SNAK
                // For some reason, for OUT endpoints, there's no mechanism to poll for
                // SNAK being enabled (eg OUTEPNE / "OUT endpoint NAK effective"),
                // like there is for IN endpoints (INEPNE / "IN endpoint NAK effective").
                DOEPCTL |= USB_OTG_DOEPCTL_SNAK;
                
                // Clear STALL (endpoint 0 doesn't support resetting STALL)
                if (i) DOEPCTL &= ~USB_OTG_DOEPCTL_STALL;
                
                // Reset PID to DATA0 (endpoint 0 doesn't support resetting PID to 0)
                if (i) DOEPCTL |= USB_OTG_DOEPCTL_SD0PID_SEVNFRM;
            }
        }
    }
    
    // Prepare to flush the FIFO
    // Before flushing the FIFO: "The application must [check] that the core
    // is neither writing to the Tx FIFO nor reading from the Tx FIFO."
    // Write: "AHBIDL bit in OTG_GRSTCTL ensures the core is not writing
    //         anything to the FIFO"
    // Read: "NAK Effective [INEPNE] interrupt ensures the core is not
    //        reading from the FIFO" (checked above)
    while (!(USBx->GRSTCTL & USB_OTG_GRSTCTL_AHBIDL));
    
    // Flush Rx FIFO
    USBx->GRSTCTL = USB_OTG_GRSTCTL_RXFFLSH;
    while (USBx->GRSTCTL & USB_OTG_GRSTCTL_RXFFLSH);
    
    // Flush all Tx FIFOs
    USBx->GRSTCTL = (USB_OTG_GRSTCTL_TXFFLSH | (0x10 << 6));
    while (USBx->GRSTCTL & USB_OTG_GRSTCTL_TXFFLSH);
    
    // Restore old NAK state
    setIgnoreOUTTransactions(pdev, oldIgnoreOUTTransactions);
    setIgnoreINTransactions(pdev, oldIgnoreINTransactions);
}

void USB::resetFinish() {
    // Reset all endpoints to return them to the default state
    resetEndpoints(&_device);
    // Reply to the reset control report
    USBD_CtlSendStatus(&_device);
}

USBD_StatusTypeDef USB::cmdRecv() {
    return USBD_LL_PrepareReceive(&_device, Endpoints::CmdOut, _cmdBuf, sizeof(_cmdBuf));
}

USBD_StatusTypeDef USB::pixSend(const void* data, size_t len) {
    // TODO: if this function is called twice, the second call will clobber the first.
    //       the second call should fail (returning BUSY) until the data is finished sending from the first call.
    return USBD_LL_Transmit(&_device, Endpoints::PixIn, (uint8_t*)data, len);
}

uint8_t USB::_usbd_Init(uint8_t cfgidx) {
    _super::_usbd_Init(cfgidx);
    
    // Open endpoints
    {
        // CmdOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::CmdOut, USBD_EP_TYPE_BULK, MaxPacketSize::Cmd);
        _device.ep_out[EndpointNum(Endpoints::CmdOut)].is_used = 1U;
        
        // PixIn endpoint is disabled by default
        USBD_LL_OpenEP(&_device, Endpoints::PixIn, USBD_EP_TYPE_BULK, MaxPacketSize::Data);
        _device.ep_in[EndpointNum(Endpoints::PixIn)].is_used = 1U;
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
    case EndpointNum(Endpoints::PixIn): {
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
    case EndpointNum(Endpoints::CmdOut): {
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
    constexpr size_t descLen = 32;
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
            0x02,                                       // bNumEndpoints
            0xFF,                                       // bInterfaceClass: vendor specific
            0x00,                                       // bInterfaceSubClass
            0x00,                                       // nInterfaceProtocol
            0x00,                                       // iInterface: string descriptor index
            
                // CmdOut endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                Endpoints::CmdOut,                                          // bEndpointAddress
                0x02,                                                       // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Cmd), HIBYTE(MaxPacketSize::Cmd),     // wMaxPacketSize
                0x00,                                                       // bInterval: ignore for Bulk transfer
                
                // PixIn endpoint
                0x07,                                                       // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                     // bDescriptorType: Endpoint
                Endpoints::PixIn,                                           // bEndpointAddress
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
