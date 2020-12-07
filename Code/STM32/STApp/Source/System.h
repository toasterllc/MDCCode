#include "SystemBase.h"
#include "QSPI.h"
#include "ICE40.h"
#include "BufQueue.h"
#include "USB.h"
#include "STAppTypes.h"

class System : public SystemBase<System> {
public:
    System();
    void init();
    
private:
    void _reset();
    void _handleEvent();
    void _handleUSBEvent(const USB::Event& ev);
    void _handleReset();
    void _handleCmd(const USB::Cmd& ev);
    void _handleQSPIEvent(const QSPI::Signal& ev);
    void _handlePixUSBEvent(const USB::Signal& ev);
    void _recvPixDataFromICE40();
    void _sendPixDataOverUSB();
    
    ICE40::SDGetStatusResp _sdGetStatus();
    ICE40::SDGetStatusResp _sdSendCmd(uint8_t sdCmd, uint32_t sdArg,
        ICE40::SDSendCmdMsg::RespType respType = ICE40::SDSendCmdMsg::RespTypes::Len48,
        ICE40::SDSendCmdMsg::DatInType datInType = ICE40::SDSendCmdMsg::DatInTypes::None);
    
    ICE40::PixGetStatusResp _pixGetStatus();
    uint16_t _pixRead(uint16_t addr);
    void _pixWrite(uint16_t addr, uint16_t val);
    
    // Peripherals
    USB _usb;
    QSPI _qspi;
    
    const STApp::PixInfo _pixInfo = {
        .width = 2304,
        .height = 1296,
    };
    bool _pixStreamEnabled = false;
    bool _pixStreamTestMode = false;
    BufQueue<2> _pixBufs;
    size_t _pixRemLen = 0;
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;
