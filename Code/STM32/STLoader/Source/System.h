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
    
    // USB
    void _usbHandleEvent(const USB::Event& ev);
    void _usbHandleCmd(const USB::Cmd& ev);
    void _usbHandleData(const USB::Data& ev);
    
    // STM32 Bootloader
    void _stStart(const STLoader::Cmd& cmd);
    void _stFinish();
    
    // ICE40 Bootloader
    void _iceStart(const STLoader::Cmd& cmd);
    void _iceHandleData(const USB::Data& ev);
    void _iceFinish();
    void _iceHandleQSPIEvent(const QSPI::Signal& ev);
    void _iceDataRecv();
    void _qspiWriteBuf();
    void _qspiWrite(const void* data, size_t len);
    
    // MSP430 Bootloader
    void _mspStart(const STLoader::Cmd& cmd);
    void _mspHandleData(const USB::Data& ev);
    void _mspFinish();
    
    USB _usb;
    QSPI _qspi;
    using _ICECRST_ = GPIO<GPIOPortI, GPIO_PIN_6>;
    using _ICECDONE = GPIO<GPIOPortI, GPIO_PIN_7>;
    using _ICESPIClk = GPIO<GPIOPortB, GPIO_PIN_2>;
    using _ICESPICS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    
    STLoader::Op _op = STLoader::Op::None;
    STLoader::Status _status __attribute__((aligned(4))) = STLoader::Status::Idle; // Needs to be aligned to send via USB
    bool _iceEndOfData = false;
    
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
