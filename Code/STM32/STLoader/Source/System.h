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
    void _finishCmd(bool status);
    
    // USB
    void _usb_cmdHandle(const USB::CmdRecv& ev);
    void _usb_dataRecvDone(const USB::DataRecv& ev);
    void _usb_dataSendReady(const USB::Event& ev);
    void _usb_recvToBuf();
    void _usb_sendFromBuf();
    
    // STM32 Bootloader
    void _stWrite(const STLoader::Cmd& cmd);
    void _stReset(const STLoader::Cmd& cmd);
    void _stHandleUSBDataRecv(const USB::DataRecv& ev);
    
    // ICE40 Bootloader
    void _iceWrite(const STLoader::Cmd& cmd);
    void _iceWriteFinish();
    void _iceUpdateState();
    void _iceHandleUSBDataRecv(const USB::DataRecv& ev);
    void _iceHandleQSPIEvent(const QSPI::Signal& ev);
    void _qspiWriteFromBuf();
    
    // MSP430 Bootloader
    void _mspConnect(const STLoader::Cmd& cmd);
    void _mspDisconnect(const STLoader::Cmd& cmd);
    
    void _mspRead(const STLoader::Cmd& cmd);
    void _mspReadFinish();
    void _mspReadUpdateState();
    void _mspReadToBuf();
    void _mspReadHandleUSBDataSend(const USB::DataSend& ev);
    
    void _mspWrite(const STLoader::Cmd& cmd);
    void _mspWriteFinish();
    void _mspWriteHandleUSBDataRecv(const USB::DataRecv& ev);
    void _mspWriteUpdateState();
    void _mspWriteFromBuf();
    
    void _mspDebug(const STLoader::Cmd& cmd);
//    void _mspDebugHandleSetPins(const STLoader::MSPDebugCmd& cmd);
    void _mspDebugPushReadBits();
    void _mspDebugHandleSBWIO(const STLoader::MSPDebugCmd& cmd);
    void _mspDebugHandleCmd(const STLoader::MSPDebugCmd& cmd);
    void _mspDebugHandleWrite(size_t len);
    void _mspDebugHandleRead(size_t len);
    
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
    bool _usbDataBusy = false;
    bool _qspiBusy = false;
    
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
