#pragma once
#include "USBBase.h"
#include "Channel.h"
#include "usbd_def.h"
#include "STLoaderTypes.h"

class USB :
public USBBase<
    // Subclass
    USB,
    // DMA=disable because we want USB to be able to write to
    // ITCM RAM (because we write to that region as a part of
    // bootloading), but DMA masters can't access it.
    false,
    // Endpoints
    STLoader::Endpoints::DataOut,
    STLoader::Endpoints::DataIn
> {
    
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
    using _super = USBBase;
    friend class USBBase;
};
