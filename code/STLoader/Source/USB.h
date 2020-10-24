#pragma once
#include "Channel.h"
#include "usbd_def.h"

class USB {
public:
    void init();
    
    // Channels
    struct CmdEvent {
        const uint8_t* data;
        size_t dataLen;
    };
    
    struct DataEvent {
        size_t dataLen;
    };
    
    USBD_StatusTypeDef stRecvCmd();
    USBD_StatusTypeDef stRecvData(void* addr, size_t len);
    USBD_StatusTypeDef stSendStatus(void* data, size_t len);
    Channel<CmdEvent, 3> stCmdChannel;
    Channel<DataEvent, 3> stDataChannel;
    
    USBD_StatusTypeDef iceRecvCmd();
    USBD_StatusTypeDef iceRecvData(void* addr, size_t len);
    USBD_StatusTypeDef iceSendStatus(void* data, size_t len);
    Channel<CmdEvent, 3> iceCmdChannel;
    Channel<DataEvent, 3> iceDataChannel;
    
private:
    USBD_HandleTypeDef _device;
    
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
    
    uint8_t _stCmdBuf[8];
    uint8_t _iceCmdBuf[8];
};
