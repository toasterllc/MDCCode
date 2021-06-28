#include "USB.h"
#include "Enum.h"
#include "STLoaderTypes.h"
using namespace STLoader;

void USB::init() {
    // Disable USB DMA because we want USB to be able to write to
    // ITCM RAM (because we write to that region as a part of
    // bootloading), but DMA masters can't access it.
    _super::init(false);
    
    // ## Set Rx/Tx FIFO sizes. Notes:
    //   - OTG HS FIFO RAM is 4096 bytes, and must be shared amongst all endpoints.
    //   - FIFO sizes (supplied as arguments below) have units of 4-byte words.
    
    // # Set Rx FIFO sizes, shared by all OUT endpoints (GRXFSIZ register):
    //   "The OTG peripheral uses a single receive FIFO that receives
    //   the data directed to all OUT endpoints."
    HAL_PCDEx_SetRxFiFo(&_pcd, 512);
    
    // # Set Tx FIFO sizes (IN endpoints; DIEPTXF0 register)
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::Control), 16);
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::STStatusIn), 64);
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::ICEStatusIn), 64);
}

USBD_StatusTypeDef USB::stCmdRecv() {
    return USBD_LL_PrepareReceive(&_device, Endpoints::STCmdOut, _stCmdBuf, sizeof(_stCmdBuf));
}

USBD_StatusTypeDef USB::stDataRecv(void* addr, size_t len) {
    return USBD_LL_PrepareReceive(&_device, Endpoints::STDataOut, (uint8_t*)addr, len);
}

USBD_StatusTypeDef USB::stStatusSend(const void* data, size_t len) {
    // TODO: if this function is called twice, the second call will clobber the first.
    //       the second call should fail (returning BUSY) until the data is finished sending from the first call.
    return USBD_LL_Transmit(&_device, Endpoints::STStatusIn, (uint8_t*)data, len);
}

USBD_StatusTypeDef USB::iceCmdRecv() {
    return USBD_LL_PrepareReceive(&_device, Endpoints::ICECmdOut, _iceCmdBuf, sizeof(_iceCmdBuf));
}

USBD_StatusTypeDef USB::iceDataRecv(void* addr, size_t len) {
    return USBD_LL_PrepareReceive(&_device, Endpoints::ICEDataOut, (uint8_t*)addr, len);
}

USBD_StatusTypeDef USB::iceStatusSend(const void* data, size_t len) {
    // TODO: if this function is called twice, the second call will clobber the first.
    //       the second call should fail (returning BUSY) until the data is finished sending from the first call.
    return USBD_LL_Transmit(&_device, Endpoints::ICEStatusIn, (uint8_t*)data, len);
}

USBD_StatusTypeDef USB::mspCmdRecv() {
    return USBD_LL_PrepareReceive(&_device, Endpoints::MSPCmdOut, _mspCmdBuf, sizeof(_mspCmdBuf));
}

USBD_StatusTypeDef USB::mspDataRecv(void* addr, size_t len) {
    return USBD_LL_PrepareReceive(&_device, Endpoints::MSPDataOut, (uint8_t*)addr, len);
}

USBD_StatusTypeDef USB::mspStatusSend(const void* data, size_t len) {
    // TODO: if this function is called twice, the second call will clobber the first.
    //       the second call should fail (returning BUSY) until the data is finished sending from the first call.
    return USBD_LL_Transmit(&_device, Endpoints::MSPStatusIn, (uint8_t*)data, len);
}

uint8_t USB::_usbd_Init(uint8_t cfgidx) {
    _super::_usbd_Init(cfgidx);
    
    // Open STM32 endpoints
    {
        // STCmdOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::STCmdOut, USBD_EP_TYPE_BULK, MaxPacketSize::Cmd);
        _device.ep_out[EndpointNum(Endpoints::STCmdOut)].is_used = 1U;
        
        // STDataOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::STDataOut, USBD_EP_TYPE_BULK, MaxPacketSize::Data);
        _device.ep_out[EndpointNum(Endpoints::STDataOut)].is_used = 1U;
        
        // STStatusIn endpoint
        USBD_LL_OpenEP(&_device, Endpoints::STStatusIn, USBD_EP_TYPE_BULK, MaxPacketSize::Status);
        _device.ep_in[EndpointNum(Endpoints::STStatusIn)].is_used = 1U;
    }
    
    // Open ICE40 endpoints
    {
        // ICECmdOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::ICECmdOut, USBD_EP_TYPE_BULK, MaxPacketSize::Cmd);
        _device.ep_out[EndpointNum(Endpoints::ICECmdOut)].is_used = 1U;
        
        // ICEDataOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::ICEDataOut, USBD_EP_TYPE_BULK, MaxPacketSize::Data);
        _device.ep_out[EndpointNum(Endpoints::ICEDataOut)].is_used = 1U;
        
        // ICEStatusIn endpoint
        USBD_LL_OpenEP(&_device, Endpoints::ICEStatusIn, USBD_EP_TYPE_BULK, MaxPacketSize::Status);
        _device.ep_in[EndpointNum(Endpoints::ICEStatusIn)].is_used = 1U;
    }
    
    // Open MSP430 endpoints
    {
        // MSPCmdOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::MSPCmdOut, USBD_EP_TYPE_BULK, MaxPacketSize::Cmd);
        _device.ep_out[EndpointNum(Endpoints::MSPCmdOut)].is_used = 1U;
        
        // MSPDataOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::MSPDataOut, USBD_EP_TYPE_BULK, MaxPacketSize::Data);
        _device.ep_out[EndpointNum(Endpoints::MSPDataOut)].is_used = 1U;
        
        // MSPStatusIn endpoint
        USBD_LL_OpenEP(&_device, Endpoints::MSPStatusIn, USBD_EP_TYPE_BULK, MaxPacketSize::Status);
        _device.ep_in[EndpointNum(Endpoints::MSPStatusIn)].is_used = 1U;
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
    return _super::_usbd_DataIn(epnum);
}

uint8_t USB::_usbd_DataOut(uint8_t epnum) {
    _super::_usbd_DataOut(epnum);
    
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
            InterfaceIdxs::STM32,                       // bInterfaceNumber: interface index
            0x00,                                       // bAlternateSetting: alternate setting
            0x03,                                       // bNumEndpoints
            0xFF,                                       // bInterfaceClass: vendor specific
            0x00,                                       // bInterfaceSubClass
            0x00,                                       // nInterfaceProtocol
            0x00,                                       // iInterface: string descriptor index
            
                // STCmdOut endpoint
                0x07,                                                           // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                         // bDescriptorType: Endpoint
                Endpoints::STCmdOut,                                            // bEndpointAddress
                0x02,                                                           // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Cmd), HIBYTE(MaxPacketSize::Cmd),         // wMaxPacketSize
                0x00,                                                           // bInterval: ignore for Bulk transfer
                
                // STDataOut endpoint
                0x07,                                                           // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                         // bDescriptorType: Endpoint
                Endpoints::STDataOut,                                           // bEndpointAddress
                0x02,                                                           // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Data), HIBYTE(MaxPacketSize::Data),       // wMaxPacketSize
                0x00,                                                           // bInterval: ignore for Bulk transfer
                
                // STStatusIn endpoint
                0x07,                                                           // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                         // bDescriptorType: Endpoint
                Endpoints::STStatusIn,                                          // bEndpointAddress
                0x02,                                                           // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Status), HIBYTE(MaxPacketSize::Status),   // wMaxPacketSize
                0x00,                                                           // bInterval: ignore for Bulk transfer
            
            // Interface descriptor: ICE40 bootloader
            0x09,                                       // bLength: interface descriptor length
            USB_DESC_TYPE_INTERFACE,                    // bDescriptorType: interface descriptor
            InterfaceIdxs::ICE40,                       // bInterfaceNumber: Number of Interface
            0x00,                                       // bAlternateSetting: Alternate setting
            0x03,                                       // bNumEndpoints
            0xFF,                                       // bInterfaceClass: vendor specific
            0x00,                                       // bInterfaceSubClass
            0x00,                                       // nInterfaceProtocol
            0x00,                                       // iInterface: string descriptor index
            
                // ICECmdOut endpoint
                0x07,                                                           // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                         // bDescriptorType: Endpoint
                Endpoints::ICECmdOut,                                           // bEndpointAddress
                0x02,                                                           // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Cmd), HIBYTE(MaxPacketSize::Cmd),         // wMaxPacketSize
                0x00,                                                           // bInterval: ignore for Bulk transfer
                
                // ICEDataOut endpoint
                0x07,                                                           // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                         // bDescriptorType: Endpoint
                Endpoints::ICEDataOut,                                          // bEndpointAddress
                0x02,                                                           // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Data), HIBYTE(MaxPacketSize::Data),       // wMaxPacketSize
                0x00,                                                           // bInterval: ignore for Bulk transfer
                
                // ICEStatusIn endpoint
                0x07,                                                           // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                         // bDescriptorType: Endpoint
                Endpoints::ICEStatusIn,                                         // bEndpointAddress
                0x02,                                                           // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Status), HIBYTE(MaxPacketSize::Status),   // wMaxPacketSize
                0x00,                                                           // bInterval: ignore for Bulk transfer
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
