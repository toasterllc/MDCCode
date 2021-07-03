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
    void _updateStatus(STLoader::Status status, bool send=false);
    
    // USB
    void _usbHandleEvent(const USB::Event& ev);
    void _usbHandleCmd(const USB::Cmd& ev);
    void _usbHandleData(const USB::Data& ev);
    void _usbDataRecv();
    
    // STM32 Bootloader
    void _stWrite(const STLoader::Cmd& cmd);
    void _stFinish(const STLoader::Cmd& cmd);
    void _stWriteFinish();
    void _stHandleUSBData(const USB::Data& ev);
    
    // ICE40 Bootloader
    void _iceWrite(const STLoader::Cmd& cmd);
    void _iceWriteFinish();
    void _iceUpdateState();
    void _iceHandleUSBData(const USB::Data& ev);
    void _iceHandleQSPIEvent(const QSPI::Signal& ev);
    void _qspiWriteBuf();
    void _qspiWrite(const void* data, size_t len);
    
    // MSP430 Bootloader
    void _mspStart(const STLoader::Cmd& cmd);
    void _mspWrite(const STLoader::Cmd& cmd);
    void _mspFinish(const STLoader::Cmd& cmd);
    void _mspWriteFinish();
    void _mspHandleUSBData(const USB::Data& ev);
    void _mspUpdateState();
    void _mspWriteBuf();
    
    // Other commands
    void _ledSet(const STLoader::Cmd& cmd);
    
    USB _usb;
    QSPI _qspi;
    using _ICECRST_ = GPIO<GPIOPortI, GPIO_PIN_6>;
    using _ICECDONE = GPIO<GPIOPortI, GPIO_PIN_7>;
    using _ICESPIClk = GPIO<GPIOPortB, GPIO_PIN_2>;
    using _ICESPICS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    
    STLoader::Op _usbDataOp = STLoader::Op::None;
    size_t _usbDataRem = 0;
    STLoader::Status _status = STLoader::Status::OK;
    
    uint32_t _mspAddr = 0;
    
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
