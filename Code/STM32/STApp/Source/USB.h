#pragma once
#include "USBBase.h"
#include "Channel.h"
#include "usbd_def.h"

class USB : public USBBase<USB> {
public:
    // Types
    struct MaxPacketSize {
        static constexpr size_t Cmd     = 8;
        static constexpr size_t Data    = 512;
    };
    
    struct Cmd {
        const uint8_t* data;
        size_t len;
    };
    
    struct PixSentEvent {};
    
    // Methods
    void init();
    
    USBD_StatusTypeDef cmdRecv();
    USBD_StatusTypeDef pixSend(void* data, size_t len);
    
    // Channels
    Channel<Cmd, 1> cmdChannel;
    Channel<PixSentEvent, 1> pixChannel;
    
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
    uint8_t _cmdBuf[MaxPacketSize::Cmd] __attribute__((aligned(4)));
    
    using _super = USBBase<USB>;
    friend class USBBase<USB>;
};
