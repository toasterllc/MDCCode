#include "GPIO.h"
#include "USB.h"
#include "QSPI.h"
#include "ICE40.h"
#include "STLoaderTypes.h"

extern "C" int main();

class System {
public:
    System();
    void init();
    
    // Peripherals
    USB usb;
    QSPI qspi;
    ICE40 ice40;
    
private:
    void _handleEvent();
    void _usbHandleEvent(const USB::Event& ev);
    void _sendSDCmd(uint8_t sdCmd, uint32_t sdArg);
    ICE40::SDGetStatusResp _getSDStatus();
    ICE40::SDGetStatusResp _getSDResp();
    
    // LEDs
    GPIO _led0;
    GPIO _led1;
    GPIO _led2;
    GPIO _led3;
    
    friend int main();
};

extern System Sys;
