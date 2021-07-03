#pragma once
#include "USBBase.h"
#include "Channel.h"
#include "usbd_def.h"

class USB : public USBBase<USB> {
public:
    // Types
    struct MaxPacketSize {
        static constexpr size_t Cmd     = 16;
        static constexpr size_t Data    = 512;
    };
    
    struct CmdRecv {
        const uint8_t* data;
        size_t len;
    };
    
    struct DataRecv {
        size_t len;
    };
    
    struct DataSend {};
    
    // Methods
    void init();
    
    USBD_StatusTypeDef cmdRecv();
    USBD_StatusTypeDef dataRecv(void* addr, size_t len);
    USBD_StatusTypeDef dataSend(const void* data, size_t len);
    
    // Channels
    Channel<CmdRecv, 1> cmdRecvChannel;
    Channel<DataRecv, 1> dataRecvChannel;
    Channel<DataSend, 1> dataSendChannel;
    
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
    uint8_t _cmdRecvBuf[MaxPacketSize::Cmd] __attribute__((aligned(4)));
    uint8_t _dataSendBuf[MaxPacketSize::Data] __attribute__((aligned(4)));
    
    bool _cmdRecvBusy = false;
    bool _dataRecvBusy = false;
    bool _dataSendBusy = false;
    
    using _super = USBBase<USB>;
    friend class USBBase<USB>;
};
