#include "USB.h"
#include "Enum.h"

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
    //   - OTG HS FIFO RAM is 4096 bytes, and must be shared amongst all endpoints.
    //   - FIFO sizes (supplied as arguments below) have units of 4-byte words.
    
    // # Set Rx FIFO sizes, shared by all OUT endpoints (GRXFSIZ register):
    //   "The OTG peripheral uses a single receive FIFO that receives
    //   the data directed to all OUT endpoints."
    HAL_PCDEx_SetRxFiFo(&_pcd, 64);
    
    // # Set Tx FIFO sizes (IN endpoints; DIEPTXF0 register)
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::Control), 16);
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::PixIn), 768);
}

USBD_StatusTypeDef USB::cmdRecv() {
    return USBD_LL_PrepareReceive(&_device, Endpoints::CmdOut, _cmdBuf, sizeof(_cmdBuf));
}

static HAL_StatusTypeDef abortEndpoint(USBD_HandleTypeDef* pdev, uint8_t ep_addr) {
  PCD_HandleTypeDef *hpcd = (PCD_HandleTypeDef*)pdev->pData;
  PCD_EPTypeDef* ep = (ep_addr&0x80 ? &hpcd->IN_ep[ep_addr&EP_ADDR_MSK] : &hpcd->OUT_ep[ep_addr&EP_ADDR_MSK]);
  ep->is_in = (ep_addr&0x80 ? 1 : 0);
  ep->num = ep_addr & EP_ADDR_MSK;
  
  USB_OTG_GlobalTypeDef *USBx = hpcd->Instance;
  uint32_t USBx_BASE = (uint32_t)USBx;
  uint32_t epnum = (uint32_t)ep->num;
  
  // Disable interrupts
  bool enirq = !__get_PRIMASK();
  __disable_irq();
  {
    if (ep->is_in == 1U) {
      auto epin = USBx_INEP(epnum);
      auto& DIEPCTL = epin->DIEPCTL;
      auto& DIEPINT = epin->DIEPINT;
      if (DIEPCTL & USB_OTG_DIEPCTL_EPENA) {
          // Enable NAK-mode (set SNAK)
          DIEPCTL |= USB_OTG_DIEPCTL_SNAK;
          // Wait for the USB core to acknowledge NAK-mode=enabled via the
          // "NAK effective" interrupt bit (INEPNE)
          while (!(DIEPINT & USB_OTG_DIEPINT_INEPNE));
          
          // Disable the endpoint (set EPDIS and SNAK)
          // TODO: revisit the clearing of USB_OTG_DIEPCTL_EPENA here,
          // to ensure we're not writing a 1 to it... is that necessary?
          DIEPCTL |= (DIEPCTL&~USB_OTG_DIEPCTL_EPENA) | USB_OTG_DIEPCTL_EPDIS | USB_OTG_DIEPCTL_SNAK;
          // Wait for the USB core to acknowledge that the endpoint is disabled
          // via the "endpoint disabled" interrupt bit (EPDISD)
          while (!(DIEPINT & USB_OTG_DIEPINT_EPDISD));
          // Verify that EPDIS is cleared: "The core clears [EPDIS] before
          // setting the endpoint disabled interrupt."
          Assert(!(DIEPCTL & USB_OTG_DIEPCTL_EPDIS));
          
          // Prepare to flush the FIFO
          // Before flushing the FIFO: "The application must [check] that the core
          // is neither writing to the Tx FIFO nor reading from the Tx FIFO."
          // Write: "AHBIDL bit in OTG_GRSTCTL ensures the core is not writing
          //         anything to the FIFO"
          // Read: "NAK Effective [INEPNE] interrupt ensures the core is not
          //        reading from the FIFO" (checked above)
          while (!(USBx->GRSTCTL & USB_OTG_GRSTCTL_AHBIDL));
          
          // Flush Tx FIFO
          USBx->GRSTCTL = (USB_OTG_GRSTCTL_TXFFLSH | (epnum << 6));
          // Wait for the FIFO to be flushed
          while (USBx->GRSTCTL & USB_OTG_GRSTCTL_TXFFLSH);
          
          // Disable NAK-mode (set SNAK)
          DIEPCTL |= USB_OTG_DIEPCTL_CNAK;
          // Wait for the USB core to acknowledge NAK-mode=disabled via the
          // "NAK effective" interrupt bit (INEPNE)
          while (DIEPINT & USB_OTG_DIEPINT_INEPNE);
      }
    
    } else {
      
    }
  }
  if (enirq) __enable_irq();

//  /* Read DEPCTLn register */
//  if (ep->is_in == 1U)
//  {
//    if ((USBx_INEP(epnum)->DIEPCTL & USB_OTG_DIEPCTL_EPENA) == USB_OTG_DIEPCTL_EPENA)
//    {
//      USBx_INEP(epnum)->DIEPCTL |= USB_OTG_DIEPCTL_SNAK;
//      USBx_INEP(epnum)->DIEPCTL |= USB_OTG_DIEPCTL_EPDIS;
//    }
//
//    USBx_DEVICE->DEACHMSK &= ~(USB_OTG_DAINTMSK_IEPM & (uint32_t)(1UL << (ep->num & EP_ADDR_MSK)));
//    USBx_DEVICE->DAINTMSK &= ~(USB_OTG_DAINTMSK_IEPM & (uint32_t)(1UL << (ep->num & EP_ADDR_MSK)));
//    USBx_INEP(epnum)->DIEPCTL &= ~(USB_OTG_DIEPCTL_USBAEP |
//                                   USB_OTG_DIEPCTL_MPSIZ |
//                                   USB_OTG_DIEPCTL_TXFNUM |
//                                   USB_OTG_DIEPCTL_SD0PID_SEVNFRM |
//                                   USB_OTG_DIEPCTL_EPTYP);
//  }
//  else
//  {
//    if ((USBx_OUTEP(epnum)->DOEPCTL & USB_OTG_DOEPCTL_EPENA) == USB_OTG_DOEPCTL_EPENA)
//    {
//      USBx_OUTEP(epnum)->DOEPCTL |= USB_OTG_DOEPCTL_SNAK;
//      USBx_OUTEP(epnum)->DOEPCTL |= USB_OTG_DOEPCTL_EPDIS;
//    }
//
//    USBx_DEVICE->DEACHMSK &= ~(USB_OTG_DAINTMSK_OEPM & ((uint32_t)(1UL << (ep->num & EP_ADDR_MSK)) << 16));
//    USBx_DEVICE->DAINTMSK &= ~(USB_OTG_DAINTMSK_OEPM & ((uint32_t)(1UL << (ep->num & EP_ADDR_MSK)) << 16));
//    USBx_OUTEP(epnum)->DOEPCTL &= ~(USB_OTG_DOEPCTL_USBAEP |
//                                    USB_OTG_DOEPCTL_MPSIZ |
//                                    USB_OTG_DOEPCTL_SD0PID_SEVNFRM |
//                                    USB_OTG_DOEPCTL_EPTYP);
//  }

  return HAL_OK;
}

USBD_StatusTypeDef USB::pixDisable() {
    abortEndpoint(&_device, Endpoints::PixIn);
//    USBD_StatusTypeDef ur = USBD_LL_CloseEP(&_device, Endpoints::PixIn);
//    Assert(ur == USBD_OK); // TOOD: error handling
    
    USBD_StatusTypeDef ur = USBD_LL_StallEP(&_device, Endpoints::PixIn);
    Assert(ur == USBD_OK); // TOOD: error handling
    
    return USBD_OK;
}

USBD_StatusTypeDef USB::pixEnable() {
//    USBD_StatusTypeDef ur = USBD_LL_OpenEP(&_device, Endpoints::PixIn, USBD_EP_TYPE_BULK, MaxPacketSize::Data);
//    Assert(ur == USBD_OK); // TOOD: error handling
    
//    // TODO: why cant this go before OpenEP? when we put it there, our writes on PixIn don't reach the host
    USBD_StatusTypeDef ur = USBD_LL_ClearStallEP(&_device, Endpoints::PixIn);
    Assert(ur == USBD_OK); // TOOD: error handling
    
    return USBD_OK;
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
        
//        pixEnable();
        // PixIn endpoint is disabled by default
        USBD_LL_OpenEP(&_device, Endpoints::PixIn, USBD_EP_TYPE_BULK, MaxPacketSize::Data);
        _device.ep_in[EndpointNum(Endpoints::PixIn)].is_used = 1U;
        pixDisable();
    }
    
    return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_DeInit(uint8_t cfgidx) {
    return _super::_usbd_DeInit(cfgidx);
}

uint8_t USB::_usbd_Setup(USBD_SetupReqTypedef* req) {
    _super::_usbd_Setup(req);
    USBD_CtlError(&_device, req);
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
        pixChannel.writeTry(DoneEvent{});
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
