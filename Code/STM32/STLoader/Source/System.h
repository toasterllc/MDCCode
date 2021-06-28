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
    
    // STM32 bootloader
    void _stHandleCmd(const USB::Cmd& ev);
    void _stHandleData(const USB::Data& ev);
    
    STLoader::STStatus _stStatus __attribute__((aligned(4))) = STLoader::STStatus::Idle;
    
    // ICE40 bootloader
    void _iceHandleCmd(const USB::Cmd& ev);
    void _iceHandleData(const USB::Data& ev);
    void _iceHandleQSPIEvent(const QSPI::Signal& ev);
    bool _iceBufEmpty();
    void _iceDataRecv();
    void _qspiWriteBuf();
    void _qspiWrite(const void* data, size_t len);
    
    // MSP430 bootloader
    void _mspHandleCmd(const USB::Cmd& ev);
    void _mspHandleData(const USB::Data& ev);
    
    USB _usb;
    QSPI _qspi;
    using _ICECRST_ = GPIO<GPIOPortI, GPIO_PIN_6>;
    using _ICECDONE = GPIO<GPIOPortI, GPIO_PIN_7>;
    using _ICESPIClk = GPIO<GPIOPortB, GPIO_PIN_2>;
    using _ICESPICS_ = GPIO<GPIOPortB, GPIO_PIN_6>;
    
    uint8_t _iceBuf0[1024];
    uint8_t _iceBuf1[1024];
    BufQueue<2> _iceBufs;
    size_t _iceRemLen = 0;
    STLoader::ICEStatus _iceStatus __attribute__((aligned(4))) = STLoader::ICEStatus::Idle;
    
    friend int main();
    friend void ISR_OTG_HS();
    friend void ISR_QUADSPI();
    friend void ISR_DMA2_Stream7();
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
};

extern System Sys;
