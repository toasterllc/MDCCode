#include "SystemBase.h"
#include "ICE40.h"
#include "QSPI.h"

class System : public SystemBase<System> {
public:
    System();
    void init();
    
private:
    using Msg = ICE40::Msg;
    using EchoMsg = ICE40::EchoMsg;
    using EchoResp = ICE40::EchoResp;
    using SDClkSrcMsg = ICE40::SDClkSrcMsg;
    using SDSendCmdMsg = ICE40::SDSendCmdMsg;
    using SDGetStatusMsg = ICE40::SDGetStatusMsg;
    using SDGetStatusResp = ICE40::SDGetStatusResp;
    using PixResetMsg = ICE40::PixResetMsg;
    using PixCaptureMsg = ICE40::PixCaptureMsg;
    using PixReadoutMsg = ICE40::PixReadoutMsg;
    using PixI2CTransactionMsg = ICE40::PixI2CTransactionMsg;
    using PixGetStatusMsg = ICE40::PixGetStatusMsg;
    using PixGetStatusResp = ICE40::PixGetStatusResp;
    
    using SDRespTypes = ICE40::SDSendCmdMsg::RespTypes;
    using SDDatInTypes = ICE40::SDSendCmdMsg::DatInTypes;
    
    void _handleEvent();
    void _usbHandleEvent(const USB::Event& ev);
    void _handleCmd(const USB::Cmd& ev);
    
    SDGetStatusResp _sdGetStatus();
    SDGetStatusResp _sdSendCmd(uint8_t sdCmd, uint32_t sdArg,
        ICE40::SDSendCmdMsg::RespType respType = ICE40::SDSendCmdMsg::RespTypes::Len48,
        ICE40::SDSendCmdMsg::DatInType datInType = ICE40::SDSendCmdMsg::DatInTypes::None);
    
    PixGetStatusResp _pixGetStatus();
    uint16_t _pixRead(uint16_t addr);
    void _pixWrite(uint16_t addr, uint16_t val);
    
    // Peripherals
    QSPI _qspi;
    ICE40 _ice40;
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;
