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
    
    void _handleEvent();
    void _finishCmd(STApp::Status status);
    
    void _usb_reset(bool usbResetFinish);
    void _usb_cmdHandle(const USB::CmdRecv& ev);
    void _usb_cmdRecv();
    void _usb_eventHandle(const USB::Event& ev);
    void _usb_sendFromBuf();
    void _usb_dataSendHandle(const USB::DataSend& ev);
    
    void _sdRead(const STApp::Cmd& cmd);
    void _sdRead_qspiReadToBuf();
    void _sdRead_qspiEventHandle(const QSPI::Signal& ev);
    void _sdRead_usbDataSendHandle(const USB::DataSend& ev);
    void _sdRead_updateState();
    void _sdRead_finish();
    
    void _ledSet(const STApp::Cmd& cmd);
    
private:
    // Peripherals
    USB _usb;
    QSPI _qspi;
    using _ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    using _ICE_ST_SPI_D_READY = GPIO<GPIOPortF, GPIO_PIN_14>;
    
    STApp::Op _op = STApp::Op::None;
    size_t _opDataRem = 0;
    bool _usbDataBusy = false;
    bool _qspiBusy = false;
    BufQueue<2> _bufs;
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;
