#pragma once
#include "USBBase.h"
#include "Channel.h"
#include "usbd_def.h"

class USB : public USBBase<USB> {
public:
    // Types
    struct MaxPacketSize {
        static constexpr size_t Cmd        = 16;
        static constexpr size_t Data       = 512;
        static constexpr size_t Status     = 8;
    };
    
    struct Cmd {
        const uint8_t* data;
        size_t len;
    };
    
    struct Data {
        size_t len;
    };
    
    // Methods
    void init();
    
    USBD_StatusTypeDef cmdRecv();
    bool cmdRecvUnderway() const;
    
    USBD_StatusTypeDef dataRecv(void* addr, size_t len);
    bool dataRecvUnderway() const;
    
    USBD_StatusTypeDef statusSend(const void* data, size_t len);
    
    // Channels
    Channel<Cmd, 1> cmdChannel;
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
    uint8_t _cmdBuf[MaxPacketSize::Cmd] __attribute__((aligned(4)));
    bool _cmdRecvUnderway = false;
    bool _dataRecvUnderway = false;
    
    using _super = USBBase<USB>;
    friend class USBBase<USB>;
};
