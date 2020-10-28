#include "GPIO.h"
#include "USB.h"
#include "QSPI.h"
#include "STLoaderTypes.h"

using namespace STLoader;

class System {
public:
    System();
    void init();
    void handleEvent();
    
    // Peripherals
    USB usb;
    QSPI qspi;
    
private:
    // USB
    void _usbHandleEvent(const USB::Event& ev);
    
    // STM32 bootloader
    void _stHandleCmd(const USB::Cmd& ev);
    void _stHandleData(const USB::Data& ev);
    
    STStatus _stStatus __attribute__((aligned(4))) = STStatus::Idle;
    
    // ICE40 bootloader
    void _iceHandleCmd(const USB::Cmd& ev);
    void _iceHandleData(const USB::Data& ev);
    void _iceHandleQSPIEvent(const QSPI::Event& ev);
    bool _iceBufEmpty();
    void _iceRecvData();
    void _qspiWriteData();
    
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
    ICEStatus _iceStatus __attribute__((aligned(4))) = ICEStatus::Idle;
    ICECDONE _iceCDONEState __attribute__((aligned(4))) = ICECDONE::Error;
    
    // LEDs
    GPIO _led0;
    GPIO _led1;
    GPIO _led2;
    GPIO _led3;
};

extern System Sys;
