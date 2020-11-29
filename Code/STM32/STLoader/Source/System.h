#include "SystemBase.h"
#include "STLoaderTypes.h"

extern "C" int main();

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
    void _iceRecvData();
    void _qspiWriteBuf();
    void _qspiWrite(const void* data, size_t len);
    
    GPIO _iceCRST_;
    GPIO _iceCDONE;
    GPIO _iceSPIClk;
    GPIO _iceSPICS_;
    
    struct ICEBuf {
        uint8_t data[1024] __attribute__((aligned(4)));
        size_t len = 0;
    };
    
    static constexpr size_t _ICEBufCount = 2;
    ICEBuf _iceBuf[_ICEBufCount];
    size_t _iceBufWPtr = 0;
    size_t _iceBufRPtr = 0;
    bool _iceBufFull = false;
    size_t _iceRemLen = 0;
    STLoader::ICEStatus _iceStatus __attribute__((aligned(4))) = STLoader::ICEStatus::Idle;
    STLoader::ICECDONE _iceCDONEState __attribute__((aligned(4))) = STLoader::ICECDONE::Error;
    
    using _super = SystemBase<System>;
    friend class SystemBase<System>;
    friend int main();
};

extern System Sys;
