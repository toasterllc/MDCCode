#pragma once

#include "usbd_ioreq.h"
#include "STLoaderTypes.h"
#include "Channel.h"

typedef struct {
    uint8_t stDataOutBuf[8];
} USBD_DFU_HandleTypeDef;

extern USBD_ClassTypeDef USBD_DFU;

struct USBCmdOutEvent {
    uint8_t* data;
    size_t dataLen;
};
extern Channel<USBCmdOutEvent, 3> USBCmdOutChannel;

struct USBDataOutEvent {
    size_t dataLen;
};
extern Channel<USBDataOutEvent, 3> USBDataOutChannel;
