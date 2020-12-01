#include "SystemBase.h"
#include "STLoaderTypes.h"
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
    void _iceHandleQSPIEvent(const QSPI::Event& ev);
    bool _iceBufEmpty();
    void _iceDataRecv();
    void _qspiWriteBuf();
    void _qspiWrite(const void* data, size_t len);
    
    QSPI _qspi;
    GPIO _iceCRST_;
    GPIO _iceCDONE;
    GPIO _iceSPIClk;
    GPIO _iceSPICS_;
    
    BufQueue<1024, 2> _iceBufs;
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
