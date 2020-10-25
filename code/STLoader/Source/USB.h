#pragma once
#include "Channel.h"
#include "usbd_def.h"

extern "C" void ISR_OTG_HS();

class USB {
public:
    // Types
    struct Cmd {
        const uint8_t* data;
        size_t len;
    };
    
    struct Data {
        size_t len;
    };
    
    struct Event {
        enum class Type : uint8_t {
            StateChanged,
        };
        Type type;
    };
    
    enum class State : uint8_t {
        Disconnected,
        Connected,
    };
    
    // Initialization
    void init();
    
    // Accessors
    State state() const;
    
    // Methods
    USBD_StatusTypeDef stRecvCmd();
    USBD_StatusTypeDef stRecvData(void* addr, size_t len);
    USBD_StatusTypeDef stSendStatus(void* data, size_t len);
    
    USBD_StatusTypeDef iceRecvCmd();
    USBD_StatusTypeDef iceRecvData(void* addr, size_t len);
    USBD_StatusTypeDef iceSendStatus(void* data, size_t len);
    
    // Channels
    Channel<Event, 1> eventChannel;
    Channel<Cmd, 1> stCmdChannel;
    Channel<Data, 1> stDataChannel;
    Channel<Cmd, 1> iceCmdChannel;
    Channel<Data, 1> iceDataChannel;
    
private:
    void _isr();
    
    USBD_HandleTypeDef _device;
    PCD_HandleTypeDef _pcd;
    State _state = State::Disconnected;
    
    uint8_t _usbd_Init(uint8_t cfgidx);
    uint8_t _usbd_DeInit(uint8_t cfgidx);
    uint8_t _usbd_Setup(USBD_SetupReqTypedef  *req);
    uint8_t _usbd_EP0_TxSent();
    uint8_t _usbd_EP0_RxReady();
    uint8_t _usbd_DataIn(uint8_t epnum);
    uint8_t _usbd_DataOut(uint8_t epnum);
    uint8_t _usbd_SOF();
    uint8_t* _usbd_GetConfigDescriptor(uint16_t *length);
    uint8_t* _usbd_GetUsrStrDescriptor(uint8_t index, uint16_t *length);
    
    uint8_t _stCmdBuf[8] __attribute__((aligned(4)));
    uint8_t _iceCmdBuf[8] __attribute__((aligned(4)));;
    
    friend void ISR_OTG_HS();
};
