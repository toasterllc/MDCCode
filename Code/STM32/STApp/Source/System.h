#include "GPIO.h"
#include "USB.h"
#include "QSPI.h"
#include "ICE40.h"
#include "STLoaderTypes.h"

extern "C" int main();

class System {
public:
    System();
    void init();
    
    // Peripherals
    USB usb;
    QSPI qspi;
    ICE40 ice40;
    
private:
    void _handleEvent();
    void _usbHandleEvent(const USB::Event& ev);
    
    using EchoMsg = ICE40::EchoMsg;
    using SDDatInType = ICE40::SDSendCmdMsg::DatInTypes;
    using SDDatOutMsg = ICE40::SDDatOutMsg;
    using SDGetStatusMsg = ICE40::SDGetStatusMsg;
    using SDGetStatusResp = ICE40::SDGetStatusResp;
    using SDRespType = ICE40::SDSendCmdMsg::RespTypes;
    using SDSendCmdMsg = ICE40::SDSendCmdMsg;
    using SDSetClkMsg = ICE40::SDSetClkMsg;
    
    SDGetStatusResp _getSDStatus();
    SDGetStatusResp _sendSDCmd(uint8_t sdCmd, uint32_t sdArg,
        ICE40::SDSendCmdMsg::RespType respType = ICE40::SDSendCmdMsg::RespTypes::Normal48,
        ICE40::SDSendCmdMsg::DatInType datInType = ICE40::SDSendCmdMsg::DatInTypes::None);
    
    // LEDs
    GPIO _led0;
    GPIO _led1;
    GPIO _led2;
    GPIO _led3;
    
    friend int main();
};

extern System Sys;
