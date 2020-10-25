#include "GPIO.h"
#include "USB.h"
#include "QSPI.h"
#include "STLoaderTypes.h"
#include <queue>

using namespace STLoader;

class System {
public:
    System();
    void init();
    void handleEvent();
    
    // Peripherals
    QSPI qspi;
    USB usb;
    
private:
    // USB
    void _usbHandleEvent(const USB::Event& ev);
    
    // STM32 bootloader
    void _stHandleCmd(const USB::Cmd& ev);
    void _stHandleData(const USB::Data& ev);
    
    STStatus _stStatus = STStatus::Idle;
    
    // ICE40 bootloader
    void _iceHandleCmd(const USB::Cmd& ev);
    void _iceHandleData(const USB::Data& ev);
    void _iceHandleQSPIEvent(const QSPI::Event& ev);
    void _iceRecvData();
    void _qspiWriteData();
    
    GPIO _iceCRST_;
    GPIO _iceCDONE;
    GPIO _iceSPIClk;
    GPIO _iceSPICS_;
    
    struct ICEBuf {
        uint8_t data[512];
        size_t len = 0;
    };
    
    ICEBuf _iceBuf[2];
    std::queue<ICEBuf*> _iceInBufs;
    std::queue<ICEBuf*> _iceOutBufs;
    size_t _iceRemLen = 0;
    ICEStatus _iceStatus = ICEStatus::Idle;
    
    // LEDs
    GPIO _led0;
    GPIO _led1;
    GPIO _led2;
    GPIO _led3;
};

extern System Sys;
