#include "USB.h"
#include "Toastbox/Enum.h"
#include "STLoaderTypes.h"
#include "Assert.h"
#include <string.h>
#include <algorithm>
using namespace STLoader;

void USB::init() {
    // Disable USB DMA because we want USB to be able to write to
    // ITCM RAM (because we write to that region as a part of
    // bootloading), but DMA masters can't access it.
    _super::init(false);
    
    // ## Set Rx/Tx FIFO sizes. Notes:
    //   - OTG HS FIFO RAM is 4096 bytes, and must be shared amongst all endpoints.
    //   - FIFO sizes (supplied as arguments below) have units of 4-byte words.
    
    constexpr size_t FIFOCapTotal       = 4096;
    constexpr size_t FIFOCapRx          = 2048;
    constexpr size_t FIFOCapTxCtrl      = USB_MAX_EP0_SIZE;
    constexpr size_t FIFOCapTxDataIn    = 1984;
    constexpr size_t SetupPacketSize    = 8;
    
    // Verify that the total memory allocated for the Rx/Tx FIFOs fits within the FIFO memory.
    static_assert(FIFOCapRx+FIFOCapTxCtrl+FIFOCapTxDataIn <= FIFOCapTotal);
    // Verify that FIFOCapRx can fit the max packet size + overhead
    // STM32 USB reference manual claims that overhead is 12 words:
    //   2 words (for the status of the control OUT data packet) +
    //   10 words (for setup packets)"
    static_assert(FIFOCapRx >= std::max(SetupPacketSize,std::max(MaxPacketSize::Cmd,MaxPacketSize::Data))+12*sizeof(uint32_t));
    // Verify that the FIFO space allocated for the DataIn endpoint is large enough
    // to fit the DataIn endpoint's max packet size
    static_assert(FIFOCapTxDataIn >= MaxPacketSize::Data);
    
    // # Set Rx FIFO sizes, shared by all OUT endpoints (GRXFSIZ register):
    //   "The OTG peripheral uses a single receive FIFO that receives
    //   the data directed to all OUT endpoints."
    HAL_PCDEx_SetRxFiFo(&_pcd, FIFOCapRx/sizeof(uint32_t));
    
    // # Set Tx FIFO sizes (IN endpoints; DIEPTXF0 register)
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::Ctrl), FIFOCapTxCtrl/sizeof(uint32_t));
    HAL_PCDEx_SetTxFiFo(&_pcd, EndpointNum(Endpoints::DataIn), FIFOCapTxDataIn/sizeof(uint32_t));
}

USBD_StatusTypeDef USB::cmdRecv() {
    Assert(!_cmdRecvBusy);
    _cmdRecvBusy = true;
    return USBD_LL_PrepareReceive(&_device, Endpoints::CmdOut, _cmdRecvBuf, sizeof(_cmdRecvBuf));
}

USBD_StatusTypeDef USB::dataRecv(void* addr, size_t len) {
    Assert(!_dataRecvBusy);
    _dataRecvBusy = true;
    return USBD_LL_PrepareReceive(&_device, Endpoints::DataOut, (uint8_t*)addr, len);
}

USBD_StatusTypeDef USB::dataSend(const void* data, size_t len) {
    Assert(!_dataSendBusy);
    _dataSendBusy = true;
    return USBD_LL_Transmit(&_device, Endpoints::DataIn, (uint8_t*)data, len);
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
        
        // DataIn endpoint
        USBD_LL_OpenEP(&_device, Endpoints::DataIn, USBD_EP_TYPE_BULK, MaxPacketSize::Data);
        _device.ep_in[EndpointNum(Endpoints::DataIn)].is_used = 1U;
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
    // DataIn endpoint
    case EndpointNum(Endpoints::DataIn):
        dataSendChannel.writeTry(DataSend{});
        _dataSendBusy = false;
        break;
    
    default:
        abort();
        break;
    }
    
    return (uint8_t)USBD_OK;
}

uint8_t USB::_usbd_DataOut(uint8_t epnum) {
    _super::_usbd_DataOut(epnum);
    
    const size_t dataLen = USBD_LL_GetRxDataSize(&_device, epnum);
    switch (epnum) {
    
    // CmdOut endpoint
    case EndpointNum(Endpoints::CmdOut):
        cmdRecvChannel.writeTry(CmdRecv{
            .data = _cmdRecvBuf,
            .len = dataLen,
        });
        _cmdRecvBusy = false;
        break;
    
    // DataOut endpoint
    case EndpointNum(Endpoints::DataOut):
        dataRecvChannel.writeTry(DataRecv{
            .len = dataLen,
        });
        _dataRecvBusy = false;
        break;
    }
    
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
                
                // DataIn endpoint
                0x07,                                                           // bLength: Endpoint Descriptor size
                USB_DESC_TYPE_ENDPOINT,                                         // bDescriptorType: Endpoint
                Endpoints::DataIn,                                              // bEndpointAddress
                0x02,                                                           // bmAttributes: Bulk
                LOBYTE(MaxPacketSize::Data), HIBYTE(MaxPacketSize::Data),       // wMaxPacketSize
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
