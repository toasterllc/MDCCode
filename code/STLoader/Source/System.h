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
    
    GPIO _iceCRST_;
    GPIO _iceCDONE;
    GPIO _iceSPIClk;
    GPIO _iceSPICS_;
    
    uint8_t _iceBuf[512];
    size_t _iceBufLen = 0;
    ICEStatus _iceStatus = ICEStatus::Idle;
    
    // LEDs
    GPIO _led0;
    GPIO _led1;
    GPIO _led2;
    GPIO _led3;
};

extern System Sys;
