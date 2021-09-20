#include "SystemBase.h"
#include "QSPI.h"
#include "ICE40.h"
#include "BufQueue.h"
#include "USB.h"
#include "STAppTypes.h"
#include "Toastbox/Task.h"

class System : public SystemBase<System> {
public:
    System();
    void init();
    [[noreturn]] void run();
    
private:
    void _usbCmd_task();
    void _usbCmd_finish(bool status);
    
    void _ice_init();
    void _ice_transferNoCS(const ICE40::Msg& msg);
    void _ice_transfer(const ICE40::Msg& msg);
    void _ice_transfer(const ICE40::Msg& msg, ICE40::Resp& resp);
    
    void _msp_init();
    
    void _sd_task();
    void _sd_setPowerEnabled(bool en);
    void _sd_init();
    ICE40::SDStatusResp _sd_status();
    ICE40::SDStatusResp _sd_sendCmd(uint8_t sdCmd, uint32_t sdArg,
        ICE40::SDSendCmdMsg::RespType respType=ICE40::SDSendCmdMsg::RespTypes::Len48,
        ICE40::SDSendCmdMsg::DatInType datInType=ICE40::SDSendCmdMsg::DatInTypes::None);
    
    void _sd_readToBuf();
    void _sd_readToBufSync(void* buf, size_t len);
    
    void _ledSet();
    
    // Peripherals
    USB _usb;
    Task _usbTask;
    
    QSPI _qspi;
    using _ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    using _ICE_ST_SPI_D_READY = GPIO<GPIOPortF, GPIO_PIN_14>;
    
    BufQueue<2> _bufs;
    
    STApp::Cmd _cmd;
    
    struct {
        Task task;
        uint16_t rca = 0;
        bool reading = false;
    } _sd;
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;
