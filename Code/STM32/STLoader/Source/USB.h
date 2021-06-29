#pragma once
#include "USBBase.h"
#include "Channel.h"
#include "usbd_def.h"

class USB : public USBBase<USB> {
public:
    // Types
    struct MaxPacketSize {
        static constexpr size_t Data       = 512;
    };
    
    struct Data {
        size_t len;
    };
    
    // Methods
    void init();
    
    USBD_StatusTypeDef dataRecv(void* addr, size_t len);
    
    // Channels
    Channel<Data, 1> dataChannel;
    
protected:
    // Callbacks
    uint8_t _usbd_Init(uint8_t cfgidx);
    uint8_t _usbd_DeInit(uint8_t cfgidx);
    uint8_t _usbd_Setup(USBD_SetupReqTypedef* req);
    uint8_t _usbd_EP0_TxSent();
    uint8_t _usbd_EP0_RxReady();
    uint8_t _usbd_DataIn(uint8_t epnum);
    uint8_t _usbd_DataOut(uint8_t epnum);
    uint8_t _usbd_SOF();
    uint8_t _usbd_IsoINIncomplete(uint8_t epnum);
    uint8_t _usbd_IsoOUTIncomplete(uint8_t epnum);
    uint8_t* _usbd_GetHSConfigDescriptor(uint16_t* len);
    uint8_t* _usbd_GetFSConfigDescriptor(uint16_t* len);
    uint8_t* _usbd_GetOtherSpeedConfigDescriptor(uint16_t* len);
    uint8_t* _usbd_GetDeviceQualifierDescriptor(uint16_t* len);
    uint8_t* _usbd_GetUsrStrDescriptor(uint8_t index, uint16_t* len);
    
private:
    using _super = USBBase<USB>;
    friend class USBBase<USB>;
};
