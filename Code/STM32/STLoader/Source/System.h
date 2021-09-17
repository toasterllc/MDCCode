#include "SystemBase.h"
#include "STLoaderTypes.h"
#include "USB.h"
#include "QSPI.h"
#include "BufQueue.h"

class System : public SystemBase<System> {
public:
    System();
    void init();
    
private:
    void _handleEvent();
    void _reset(const STLoader::Cmd& cmd);
    void _finishCmd(bool status);
    
    // USB
    void _usb_cmdHandle(const USB::CmdRecvEvent& ev);
    void _usb_recvDone(const USB::RecvDoneEvent& ev);
    void _usb_sendReady(const USB::SendReadyEvent& ev);
    void _usb_recvToBuf();
    void _usb_sendFromBuf();
    
    // STM32 Bootloader
    void _stm_write(const STLoader::Cmd& cmd);
    void _stm_reset(const STLoader::Cmd& cmd);
    void _stm_usbRecvDone(const USB::RecvDoneEvent& ev);
    
    // ICE40 Bootloader
    void _ice_write(const STLoader::Cmd& cmd);
    void _ice_writeFinish();
    void _ice_updateState();
    void _ice_usbRecvDone(const USB::RecvDoneEvent& ev);
    void _ice_qspiHandleEvent(const QSPI::Event& ev);
    void _ice_writeFromBuf();
    
    // MSP430 Bootloader
    void _msp_connect(const STLoader::Cmd& cmd);
    void _msp_disconnect(const STLoader::Cmd& cmd);
    
    void _mspRead(const STLoader::Cmd& cmd);
    void _mspRead_finish();
    void _mspRead_updateState();
    void _mspRead_readToBuf();
    void _mspRead_usbSendReady(const USB::SendReadyEvent& ev);
    
    void _mspWrite(const STLoader::Cmd& cmd);
    void _mspWrite_finish();
    void _mspWrite_usbRecvDone(const USB::RecvDoneEvent& ev);
    void _mspWrite_updateState();
    void _mspWrite_writeFromBuf();
    
    void _mspDebug(const STLoader::Cmd& cmd);
    void _mspDebug_pushReadBits();
    void _mspDebug_handleSBWIO(const STLoader::MSPDebugCmd& cmd);
    void _mspDebug_handleCmd(const STLoader::MSPDebugCmd& cmd);
    void _mspDebug_handleWrite(size_t len);
    void _mspDebug_handleRead(size_t len);
    
    // Other commands
    void _ledSet(const STLoader::Cmd& cmd);
    
    USB _usb;
    QSPI _qspi;
    using _ICE_CRST_ = GPIO<GPIOPortI, GPIO_PIN_6>;
    using _ICE_CDONE = GPIO<GPIOPortI, GPIO_PIN_7>;
    using _ICE_ST_SPI_CLK = GPIO<GPIOPortB, GPIO_PIN_2>;
    using _ICE_ST_SPI_CS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    
    STLoader::Op _op = STLoader::Op::None;
    size_t _opDataRem = 0;
    
    uint32_t _mspAddr = 0;
    
    struct {
        uint8_t bits = 0;
        uint8_t bitsLen = 0;
        size_t len = 0;
    } _mspDebugRead;
    
    uint8_t _buf0[1024] __attribute__((aligned(4))); // Needs to be aligned to send via USB
    uint8_t _buf1[1024] __attribute__((aligned(4)));
    BufQueue<2> _bufs;
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;
