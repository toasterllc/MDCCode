#pragma once
#include "Channel.h"
#include "usbd_def.h"

class USB {
public:
    void init();
    
    USBD_StatusTypeDef recvCmdOut();
    USBD_StatusTypeDef recvDataOut(void* addr, size_t len);
    USBD_StatusTypeDef sendCmdIn(void* data, size_t len);
    
    // Channels
    struct CmdOutEvent {
        uint8_t* data;
        size_t dataLen;
    };
    
    struct DataOutEvent {};
    
    Channel<CmdOutEvent, 3> cmdOutChannel;
    Channel<DataOutEvent, 3> dataOutChannel;
    
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
    
    uint8_t _cmdOutBuf[8];
};
