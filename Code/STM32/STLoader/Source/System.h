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
    
    // USB
    void _usbCmd_task();
    void _usbCmd_finish(bool status);
    void _usbDataOut_task();
    void _usbDataIn_sendStatus(bool status);
    
    // STM32 Bootloader
    void _stm_task();
    
    // ICE40 Bootloader
    void _ice_task();
    void _ice_write(const STLoader::Cmd& cmd);
    bool _ice_writeFinish();
    
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
    
    struct {
        Task task;
    } _usbCmd;
    
    struct {
        Task task;
    } _usbDataOut;
    
    struct {
        alignas(4) bool status = false; // Aligned to send via USB
    } _usbDataIn;
    
    struct {
        Task task;
        std::optional<STApp::Cmd> cmd;
    } _stm;
    
    struct {
        Task task;
        std::optional<STApp::Cmd> cmd;
    } _ice;
    
    uint32_t _mspAddr = 0;
    
    struct {
        uint8_t bits = 0;
        uint8_t bitsLen = 0;
        size_t len = 0;
    } _mspDebugRead;
    
    alignas(4) uint8_t _buf0[1024]; // Aligned to send via USB
    alignas(4) uint8_t _buf1[1024]; // Aligned to send via USB
    BufQueue<2> _bufs;
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;
