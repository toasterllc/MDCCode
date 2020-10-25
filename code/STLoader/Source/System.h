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
    void _handleSTCmd(const USB::CmdEvent& ev);
    void _handleSTData(const USB::DataEvent& ev);
    
    void _handleICECmd(const USB::CmdEvent& ev);
    void _handleICEData(const USB::DataEvent& ev);
    
    // STM32 bootloader
    STStatus _stStatus = STStatus::Idle;
    
    // ICE40 bootloader
    GPIO _iceCRST_;
    GPIO _iceCDONE;
    GPIO _iceSPIClk;
    GPIO _iceSPICS_;
    ICEStatus _iceStatus = ICEStatus::Idle;
    
    struct ICEBuf {
        uint8_t buf[512];
        size_t len;
    };
    
    ICEBuf _iceBuf[2];
    ICEBuf* _iceBufIn = nullptr;
    ICEBuf* _iceBufOut = nullptr;
    
    // LEDs
    GPIO _led0;
    GPIO _led1;
    GPIO _led2;
    GPIO _led3;
};

extern System Sys;
