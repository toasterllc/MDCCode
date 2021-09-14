#pragma once
#include "USBBase.h"
#include "Channel.h"
#include "usbd_def.h"
#include "STAppTypes.h"
#include <atomic>

class USB :
public USBBase<
    // Subclass
    USB,
    // DMA=enabled
    true,
    // Endpoints
    STApp::Endpoints::DataIn
> {
public:
    struct ResetRecv {};
    
    struct CmdRecv {
        const uint8_t* data;
        size_t len;
    };
    
    struct DataSend {};
    
    // Methods
    Channel<CmdRecv, 1> cmdRecvChannel;
    void cmdSendStatus(bool status);
    
    USBD_StatusTypeDef dataSend(const void* data, size_t len);
    void dataSendReset(); // Sends 2 zero-length packets + 1-byte sentinel
    bool dataSendReady() const;
    Channel<DataSend, 1> dataSendReadyChannel; // Signals that more data can be sent
    
protected:
    void _dataSendReset();
    void _dataSendAdvanceState();
    
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
    enum class _DataSendState {
        Reset,
        ResetZLP1,
        ResetZLP2,
        ResetSentinel,
        Ready,
        Busy,
    };
    
    static const inline uint8_t _ResetSentinel = 0;
    
    uint8_t _cmdRecvBuf[MaxPacketSizeCtrl] __attribute__((aligned(4)));
    
    _DataSendState _dataSendState = _DataSendState::Reset;
    bool _dataSendNeedsReset = false;
    
    using _super = USBBase;
    friend class USBBase;
};
