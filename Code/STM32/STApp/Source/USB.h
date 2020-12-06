#pragma once
#include "USBBase.h"
#include "Channel.h"
#include "usbd_def.h"
#include <atomic>

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
    
    struct Signal {};
    
    // Methods
    void init();
    
    // Reset
    Channel<Signal, 1> resetChannel; // Signals that a reset was requested
    void resetFinish(); // Call to complete resetting
    
    // Command input
    Channel<Cmd, 1> cmdChannel;
    USBD_StatusTypeDef cmdRecv(); // Arranges for another command to be received
    
    // Pixel data output
    Channel<Signal, 1> pixChannel; // Signals that the previous pixSend() is complete
    USBD_StatusTypeDef pixSend(const void* data, size_t len);
    
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
    bool _resetDone = false;
    
    using _super = USBBase<USB>;
    friend class USBBase<USB>;
};
