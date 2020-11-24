#include "SystemBase.h"
#include "ICE40.h"

extern "C" int main();

class System : public SystemBase<System> {
public:
    System();
    void init();
    
    // Peripherals
    ICE40 ice40;
    
private:
    void _handleEvent();
    void _usbHandleEvent(const USB::Event& ev);
    
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
    
    SDGetStatusResp _sdGetStatus();
    SDGetStatusResp _sdSendCmd(uint8_t sdCmd, uint32_t sdArg,
        ICE40::SDSendCmdMsg::RespType respType = ICE40::SDSendCmdMsg::RespTypes::Len48,
        ICE40::SDSendCmdMsg::DatInType datInType = ICE40::SDSendCmdMsg::DatInTypes::None);
    
    PixGetStatusResp _pixGetStatus();
    uint16_t _pixRead(uint16_t addr);
    void _pixWrite(uint16_t addr, uint16_t val);
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
    friend int main();
};

extern System Sys;
