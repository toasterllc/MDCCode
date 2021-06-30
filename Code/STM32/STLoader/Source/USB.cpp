#include "USB.h"
#include "Enum.h"
#include "STLoaderTypes.h"
#include "Assert.h"
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
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::Ctrl), 16);
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::StatusIn), 64);
}

USBD_StatusTypeDef USB::cmdRecv() {
    Assert(!_cmdRecvUnderway);
    _cmdRecvUnderway = true;
    return USBD_LL_PrepareReceive(&_device, Endpoints::CmdOut, _cmdBuf, sizeof(_cmdBuf));
}

USBD_StatusTypeDef USB::dataRecv(void* addr, size_t len) {
    Assert(!_dataRecvUnderway);
    _dataRecvUnderway = true;
    return USBD_LL_PrepareReceive(&_device, Endpoints::DataOut, (uint8_t*)addr, len);
}

USBD_StatusTypeDef USB::statusSend(const void* data, size_t len) {
    // TODO: if this function is called twice, the second call will clobber the first.
    //       the second call should fail (returning BUSY) until the data is finished sending from the first call.
    return USBD_LL_Transmit(&_device, Endpoints::StatusIn, (uint8_t*)data, len);
}

uint8_t USB::_usbd_Init(uint8_t cfgidx) {
    _super::_usbd_Init(cfgidx);
    
    // Open endpoints
    {
        // CmdOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::CmdOut, USBD_EP_TYPE_BULK, MaxPacketSize::Cmd);
        _device.ep_out[EndpointNum(Endpoints::CmdOut)].is_used = 1U;
        
        // DataOut endpoint
        USBD_LL_OpenEP(&_device, Endpoints::DataOut, USBD_EP_TYPE_BULK, MaxPacketSize::Data);
        _device.ep_out[EndpointNum(Endpoints::DataOut)].is_used = 1U;
        
        // StatusIn endpoint
        USBD_LL_OpenEP(&_device, Endpoints::StatusIn, USBD_EP_TYPE_BULK, MaxPacketSize::Status);
        _device.ep_in[EndpointNum(Endpoints::StatusIn)].is_used = 1U;
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
    
    // CmdOut endpoint
    case EndpointNum(Endpoints::CmdOut): {
        cmdChannel.writeTry(Cmd{
            .data = _cmdBuf,
            .len = dataLen,
        });
        _cmdRecvUnderway = false;
        break;
    }
    
    // DataOut endpoint
    case EndpointNum(Endpoints::DataOut): {
        dataChannel.writeTry(Data{
            .len = dataLen,
        });
        _dataRecvUnderway = false;
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
    constexpr size_t DescLen = 39;
    static uint8_t Desc[] = {
        // Configuration descriptor
        0x09,                                       // bLength: configuration descriptor length
        USB_DESC_TYPE_CONFIGURATION,                // bDescriptorType: configuration descriptor
        LOBYTE(DescLen), HIBYTE(DescLen),           // wTotalLength: total descriptor length
        0x02,                                       // bNumInterfaces: 2 interfaces
        0x01,                                       // bConfigurationValue: config 1
        0x00,                                       // iConfiguration: string descriptor index
        0x80,                                       // bmAttributes: bus powered
        0xFA,                                       // bMaxPower: 500 mA (2 mA units)
        
            // Interface descriptor: STM32 bootloader
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
                0x07,                                                           // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                         // bDescriptorType: Endpoint
                Endpoints::CmdOut,                                              // bEndpointAddress
                0x02,                                                           // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Cmd), HIBYTE(MaxPacketSize::Cmd),         // wMaxPacketSize
                0x00,                                                           // bInterval: ignore for Bulk transfer
                
                // DataOut endpoint
                0x07,                                                           // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                         // bDescriptorType: Endpoint
                Endpoints::DataOut,                                             // bEndpointAddress
                0x02,                                                           // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Data), HIBYTE(MaxPacketSize::Data),       // wMaxPacketSize
                0x00,                                                           // bInterval: ignore for Bulk transfer
                
                // StatusIn endpoint
                0x07,                                                           // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                         // bDescriptorType: Endpoint
                Endpoints::StatusIn,                                            // bEndpointAddress
                0x02,                                                           // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Status), HIBYTE(MaxPacketSize::Status),   // wMaxPacketSize
                0x00,                                                           // bInterval: ignore for Bulk transfer
    };
    static_assert(sizeof(Desc)==DescLen, "descLen invalid");
    
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
