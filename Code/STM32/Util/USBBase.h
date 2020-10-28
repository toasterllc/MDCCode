#pragma once
#include "Channel.h"
#include "usbd_def.h"

extern "C" void ISR_OTG_HS();

class USBBase {
public:
    // Types
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
    
    // Channels
    Channel<Event, 1> eventChannel;
    
protected:
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
    uint8_t _usbd_IsoINIncomplete(uint8_t epnum);
    uint8_t _usbd_IsoOUTIncomplete(uint8_t epnum);
    uint8_t* _usbd_GetHSConfigDescriptor(uint16_t *length);
    uint8_t* _usbd_GetFSConfigDescriptor(uint16_t *length);
    uint8_t* _usbd_GetOtherSpeedConfigDescriptor(uint16_t *length);
    uint8_t* _usbd_GetDeviceQualifierDescriptor(uint16_t *length);
    uint8_t* _usbd_GetUsrStrDescriptor(uint8_t index, uint16_t *length);
    
    uint8_t _stCmdBuf[MaxPacketSize::Cmd] __attribute__((aligned(4)));
    uint8_t _iceCmdBuf[MaxPacketSize::Cmd] __attribute__((aligned(4)));
    
    friend void ISR_OTG_HS();
};
