#pragma once
#include "USBBase.h"
#include "Channel.h"
#include "usbd_def.h"

class USB : public USBBase<USB> {
public:
    // Types
    struct Cmd {
        const uint8_t* data;
        size_t len;
    };
    
    struct Data {
        size_t len;
    };
    
    struct MaxPacketSize {
        static constexpr size_t Cmd        = 8;
        static constexpr size_t Status     = 8;
        static constexpr size_t Data       = 512;
    };
    
    // Methods
    void init();
    
    USBD_StatusTypeDef stRecvCmd();
    USBD_StatusTypeDef stRecvData(void* addr, size_t len);
    USBD_StatusTypeDef stSendStatus(void* data, size_t len);
    
    USBD_StatusTypeDef iceRecvCmd();
    USBD_StatusTypeDef iceRecvData(void* addr, size_t len);
    USBD_StatusTypeDef iceSendStatus(void* data, size_t len);
    
    // Channels
    Channel<Cmd, 1> stCmdChannel;
    Channel<Data, 1> stDataChannel;
    Channel<Cmd, 1> iceCmdChannel;
    Channel<Data, 1> iceDataChannel;
    
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
    
    uint8_t _stCmdBuf[MaxPacketSize::Cmd] __attribute__((aligned(4)));
    uint8_t _iceCmdBuf[MaxPacketSize::Cmd] __attribute__((aligned(4)));
    
    friend class USBBase<USB>;
};
